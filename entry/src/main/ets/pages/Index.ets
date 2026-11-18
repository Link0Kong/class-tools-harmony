import { Services } from '../app/Services';
import { AppGlobal } from '../app/AppGlobal';
import { Session } from '../data/session/Session';
import { Blob, JsonBlob } from '../data/sync/JsonBlob';
import { UserdataPullResult } from '../data/sync/UserdataRepository';
import { Tokens } from '../ui/theme/Tokens';
import { Motion } from '../ui/theme/Motion';
import { BootSplash } from '../ui/components/BootSplash';
import { AmbientBackdrop } from '../ui/components/AmbientBackdrop';
import { IdentityScreen } from '../ui/screens/IdentityScreen';
import { AppShell } from '../ui/shell/AppShell';
import { Device } from '../common/Device';
import { WatchShell } from '../ui/watch/WatchShell';
import { WatchLogin } from '../ui/watch/WatchLogin';
import { ToolScreen } from '../ui/tools/ToolScreen';
import { Log } from '../common/Log';
import { AppPush } from '../features/push/AppPush';
import { NotifyCenter } from '../data/notify/NotifyCenter';
import { AppUpdate } from '../features/update/AppUpdate';

const TAG: string = 'Index';

/**
 * 应用根：启动 → 身份门禁 → 三 Tab 外壳 → 工具页。
 *
 * 门禁语义与网页/小程序/安卓一致：无有效会话一律先身份页，不允许绕过；
 * 任一数据请求 401/403 由 HttpClient 回调清会话回身份页。
 */
@Entry
@Component
struct Index {
  @State private phase: string = 'boot';
  @State private userName: string = '';
  @State private maskedSid: string = '';
  @State private roleLabel: string = '';
  @State private isAdmin: boolean = false;
  @State private openToolId: string = '';
  @State private authNotice: string = '';
  @State private wearable: boolean = Device.isWearable();
  @State private quickIds: string[] = [];
  @State private syncState: string = '未同步';
  @State private splashOn: boolean = true;
  @State private splashLeaving: boolean = false;

  private session: Session | undefined = undefined;
  private homeMounted: boolean = false;
  private appReady: boolean = false;

  aboutToAppear(): void {
    Services.api.setTokenProvider(() => this.session !== undefined ? this.session.token : '');
    Services.api.setTokenInvalidHandler(() => {
      this.handleTokenInvalid();
    });
    Services.userdata.onSectionsChanged((sections: Blob) => {
      this.applySections(sections);
    });
    AppGlobal.onToolClosed = () => {
      this.openToolId = '';
    };
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    const started: number = Date.now();
    const saved: Session | undefined = await Services.sessionStore.load();
    // 冷启动仅保留短暂衔接，加载动画期间不空等
    const wait: number = 260 - (Date.now() - started);
    if (wait > 0) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, wait);
      });
    }
    if (saved !== undefined && saved.isLikelyValid(Date.now())) {
      Log.i(TAG, '已恢复本机会话，直接进入');
      await this.enterApp(saved);
      return;
    }
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.phase = 'auth';
    });
    setTimeout(() => {
      if (this.phase === 'auth') {
        this.splashOn = false;
      }
    }, 260);
  }

  private maybeLeaveSplash(): void {
    if (!this.splashOn || this.splashLeaving || !this.homeMounted || !this.appReady) {
      return;
    }
    this.splashLeaving = true;
  }

  private async enterApp(session: Session): Promise<void> {
    this.session = session;
    this.userName = session.name;
    this.maskedSid = session.maskedSid();
    this.isAdmin = session.isAdmin;
    this.roleLabel = session.isAdmin ? '管理员' : session.role;
    this.authNotice = '';
    this.getUIContext().animateTo({ duration: Motion.SLOW, curve: Motion.ease() }, () => {
      this.phase = 'app';
    });

    Services.currentSid = session.sid;
    Services.currentName = session.name;
    Services.currentToken = session.token;
    Services.currentIsAdmin = session.isAdmin;
    // 先恢复本机偏好（离线/未同步时 UI 也看到上次设置），再后台拉云端
    await Services.userdata.hydrateFromLocal();
    await Services.notices.hydrate();
    this.applySections(Services.userdata.currentSections());
    this.syncNow();
    this.appReady = true;
    if (this.wearable) {
      this.homeMounted = true;
    }
    this.maybeLeaveSplash();
    setTimeout(() => {
      this.homeMounted = true;
      this.maybeLeaveSplash();
    }, 900);
    // 用户偏好恢复后再申请通知权限/续订 token，避免启动早期写入被 hydrate 覆盖
    AppPush.syncOnLaunch();
    NotifyCenter.syncAll();
    Services.visits.reportOnce();
    setTimeout(() => {
      AppUpdate.check(false);
    }, 2000);
  }

  private applySections(sections: Blob): void {
    const raw: Object[] | undefined = JsonBlob.asArray(JsonBlob.get(sections, 'homeTools'));
    const ids: string[] = [];
    if (raw !== undefined) {
      for (let i = 0; i < raw.length; i++) {
        const id: string = JsonBlob.asString(raw[i], '');
        if (id.length > 0) {
          ids.push(id);
        }
      }
    }
    this.quickIds = ids;
  }

  /** 首页快捷写回 userdata（经仓库做脏检测 + 防抖推送 + 跨端同步）。 */
  private async setHomeTools(ids: string[]): Promise<void> {
    const current: Blob = Services.userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const arr: Object[] = [];
    for (let i = 0; i < ids.length; i++) {
      arr.push(ids[i]);
    }
    next['homeTools'] = arr;
    this.quickIds = ids;
    await Services.userdata.updateCurrent(next);
  }

  private async syncNow(): Promise<void> {
    if (Services.currentSid.length === 0) {
      return;
    }
    this.syncState = '同步中';
    // 名单/班级信息与 userdata 拉取并行，不阻塞首页
    Services.members.load(false);
    Services.league.load(false);
    const pull: UserdataPullResult = await Services.userdata.pull(false);
    if (!pull.ok()) {
      this.syncState = pull.status === 'disabled' ? '云同步已关闭' : '离线';
      return;
    }
    this.applySections(Services.userdata.currentSections());
    this.syncState = '已同步';
  }

  private async handleTokenInvalid(): Promise<void> {
    Log.w(TAG, '身份失效，清除会话并回到身份页');
    this.session = undefined;
    // 先按旧 sid 清掉通知缓存，再重置身份，避免下一位登录者看到上一位的通知
    await Services.notices.clearLocal();
    Services.currentSid = '';
    Services.currentName = '';
    Services.currentToken = '';
    Services.currentIsAdmin = false;
    Services.cloudspace.reset();
    Services.sessionStore.clear();
    AppGlobal.openToolId = '';
    this.openToolId = '';
    this.authNotice = '身份已失效，请重新输入学号与姓名';
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.phase = 'auth';
    });
  }

  private async logout(): Promise<void> {
    // 退出前尽力把本机改动推上去，再清空本机数据桶（合规：不留班级数据）
    await Services.userdata.flush();
    this.session = undefined;
    await Services.notices.clearLocal();
    await Services.userdata.clearLocal();
    await Services.members.clear();
    await Services.league.clear();
    Services.currentSid = '';
    Services.currentName = '';
    Services.currentToken = '';
    Services.currentIsAdmin = false;
    Services.cloudspace.reset();
    await Services.sessionStore.clear();
    AppGlobal.openToolId = '';
    this.openToolId = '';
    this.userName = '';
    this.maskedSid = '';
    this.roleLabel = '';
    this.isAdmin = false;
    this.authNotice = '';
    this.quickIds = [];
    this.syncState = '未同步';
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.phase = 'auth';
    });
  }

  private openTool(id: string): void {
    if (this.wearable) {
      return;
    }
    AppGlobal.openToolId = id;
    this.getUIContext().animateTo({ duration: Tokens.DUR_NORMAL, curve: Curve.FastOutSlowIn }, () => {
      this.openToolId = id;
    });
  }

  private closeTool(): void {
    AppGlobal.openToolId = '';
    this.getUIContext().animateTo({ duration: Tokens.DUR_FAST, curve: Curve.FastOutSlowIn }, () => {
      this.openToolId = '';
    });
  }

  onBackPress(): boolean {
    if (this.openToolId.length > 0) {
      this.closeTool();
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      AmbientBackdrop()
      if (this.phase === 'auth') {
        if (this.wearable) {
          WatchLogin({
            notice: this.authNotice,
            onSignedIn: (session: Session) => {
              this.enterApp(session);
            }
          })
        } else {
          IdentityScreen({
            notice: this.authNotice,
            onSignedIn: (session: Session) => {
              this.enterApp(session);
            }
          })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.99, y: 0.99 })))
        }
      } else if (this.phase === 'app') {
        if (this.wearable) {
          WatchShell({
            userName: this.userName,
            onLogout: () => {
              this.logout();
            }
          })
        } else {
          AppShell({
          userName: this.userName,
          maskedSid: this.maskedSid,
          roleLabel: this.roleLabel,
          isAdmin: this.isAdmin,
          quickIds: this.quickIds,
          syncState: this.syncState,
          onOpenTool: (id: string) => {
            this.openTool(id);
          },
          onHomeReady: () => {
            this.homeMounted = true;
            this.maybeLeaveSplash();
          },
          onSetHomeTools: (ids: string[]) => {
            this.setHomeTools(ids);
          },
          onSyncNow: () => {
            this.syncNow();
          },
          onLogout: () => {
            this.logout();
          }
        })
        }
      }

      if (this.splashOn) {
        BootSplash({
          leaving: this.splashLeaving,
          barHandoff: !this.wearable,
          onDone: () => {
            this.splashOn = false;
          }
        })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Motion.ease() }))
      }

      if (this.openToolId.length > 0) {
        ToolScreen({
          toolId: this.openToolId,
          onClose: () => {
            this.closeTool();
          }
        })
          .transition(TransitionEffect.asymmetric(Motion.pageEnter(), Motion.pageExit()))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
