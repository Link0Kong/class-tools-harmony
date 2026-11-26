import { BusinessError } from '@ohos.base';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { SessionInfo, TtPeriods, TtPlan, TtSnapshot } from '../../data/timetable/TimetableModels';
import { TtCalendar } from '../../data/timetable/TtCalendar';
import { TtResult } from '../../data/timetable/TimetableRepository';
import { TtLoginEnqueue, TtLoginStatus } from '../../data/timetable/TimetableLoginRepository';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { UserdataRepository } from '../../data/sync/UserdataRepository';
import { JwCardDef, JwEntries, JwLogic } from '../../features/jw/JwModels';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';

/**
 * 教务工具（链接型，与网页口径一致）：
 *
 * - 打开学校教务系统（`http://210.34.74.77/sso.jsp`，系统浏览器登录后自动填充）；
 * - 课表速览：当前周 / 今日课程 / 下一节（复用课表快照，不访问教务接口）；
 * - 个人课表同步：提交教务密码 → 云端 agent 登录 → 轮询结果写 `userdata.tt`（密码只随请求提交，不落盘/不打印；`p_platform='android'` 复用既有协议）；
 * - 成绩/考试/选课/公告仍不抓取。
 */
@Component
export struct JwScreen {
  onClose: () => void = () => {
  };

  @State private snapshot: TtSnapshot | undefined = undefined;
  @State private plan: TtPlan = new TtPlan();
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private refreshing: boolean = false;
  @State private now: number = Date.now();
  private scroller: Scroller = new Scroller();
  @State private pwd: string = '';
  @State private loginBusy: boolean = false;
  @State private loginMsg: string = '';
  @State private loginOk: boolean = false;
  private pollTimer: number = -1;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async submitLogin(): Promise<void> {
    if (this.loginBusy) {
      return;
    }
    const password: string = this.pwd;
    this.pwd = '';
    if (password.length === 0) {
      this.loginMsg = '请输入教务密码';
      return;
    }
    this.loginBusy = true;
    this.loginOk = false;
    this.loginMsg = '正在提交登录任务…';
    const userdata = Services.userdata;
    const enqueue: TtLoginEnqueue = await Services.login.enqueue(password);
    if (userdata !== Services.userdata) return;
    if (!enqueue.ok || enqueue.jobId.length === 0) {
      this.loginBusy = false;
      this.loginMsg = enqueue.message.length > 0 ? enqueue.message : '登录任务提交失败';
      return;
    }
    this.loginMsg = enqueue.reused ? '已复用进行中的登录任务…' : '已提交，等待云端教务返回…';
    this.pollLogin(enqueue.jobId, Date.now(), userdata);
  }

  private pollLogin(jobId: string, startedAt: number, userdata: UserdataRepository): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
    }
    this.pollTimer = setTimeout(async () => {
      this.pollTimer = -1;
      if (userdata !== Services.userdata) return;
      const status: TtLoginStatus = await Services.login.status(jobId);
      if (userdata !== Services.userdata) return;
      if (!status.ok) {
        this.loginBusy = false;
        this.loginMsg = status.message.length > 0 ? status.message : '状态查询失败';
        return;
      }
      if (!status.finished) {
        if (Date.now() - startedAt > 120000) {
          this.loginBusy = false;
          this.loginMsg = '登录超时，请稍后重试';
          return;
        }
        this.loginMsg = '云端教务处理中（' + (status.status.length > 0 ? status.status : 'running') + '）…';
        this.pollLogin(jobId, startedAt, userdata);
        return;
      }
      if (status.snapshot === undefined || status.raw === undefined || status.snapshot.c.length === 0) {
        this.loginBusy = false;
        this.loginMsg = status.error.length > 0 ? ('登录失败：' + status.error) : '未获取到课程，请稍后重试';
        return;
      }
      await this.savePersonal(status.raw, userdata);
      if (userdata !== Services.userdata) return;
      await Services.timetable.load(true);
      await this.load();
      this.loginBusy = false;
      this.loginOk = true;
      this.loginMsg = '已同步 ' + status.snapshot.c.length + ' 节课到「我的课表」';
    }, 2000);
  }

  private async savePersonal(raw: Blob, userdata: UserdataRepository): Promise<void> {
    const current: Blob = userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const tt: Blob = {};
    const oldTt: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'tt'));
    if (oldTt !== undefined) {
      const oldKeys: string[] = JsonBlob.keys(oldTt);
      for (let i = 0; i < oldKeys.length; i++) {
        tt[oldKeys[i]] = oldTt[oldKeys[i]];
      }
    }
    tt['ttUseMine'] = true;
    tt['ttLocal'] = raw;
    next['tt'] = tt;
    await userdata.saveAndPush(next, 'tt');
  }

  private async load(): Promise<void> {
    this.loading = this.snapshot === undefined;
    this.errorMsg = '';
    const result: TtResult = await Services.timetable.load(false);
    this.now = Date.now();
    this.snapshot = result.snapshot;
    this.plan = TtCalendar.plan(result.snapshot, this.now);
    if (!result.ok) {
      this.errorMsg = result.message;
    }
    this.loading = false;
  }

  private async openJw(): Promise<void> {
    const context = AppGlobal.context;
    if (context === undefined) {
      this.errorMsg = '应用上下文缺失，无法打开浏览器';
      return;
    }
    try {
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: JwEntries.url()
      });
    } catch (e) {
      const err = e as BusinessError;
      this.errorMsg = '无法打开浏览器（' + err.code + '），请在浏览器访问 ' + JwEntries.url();
    }
  }

  private todaySessions(): SessionInfo[] {
    return this.plan.today;
  }

  private nextToday(): SessionInfo | undefined {
    for (let i = 0; i < this.plan.today.length; i++) {
      if (this.plan.today[i].state !== 'done') {
        return this.plan.today[i];
      }
    }
    return undefined;
  }

  private todayText(): string {
    const next: SessionInfo | undefined = this.nextToday();
    return JwLogic.todayText(this.plan.today.length,
      next !== undefined ? next.startText : '', next !== undefined ? next.name : '');
  }

  @Builder
  loginCard() {
    Column() {
      Row() {
        Text('同步个人课表')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('教务密码')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Text('使用当前身份学号登录教务，成功后课表切换为「我的课表」。密码只用于本次登录任务，不保存。')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 6 })

      Row({ space: 8 }) {
        TextInput({ text: this.pwd, placeholder: '教务密码' })
          .type(InputType.Password)
          .layoutWeight(1)
          .height(42)
          .backgroundColor(Tokens.CONTROL)
          .fontSize(Tokens.F_CAPTION)
          .borderRadius(10)
          .onChange((value: string) => {
            this.pwd = value;
          })
        Button(this.loginBusy ? '同步中…' : '登录并同步')
          .height(42)
          .fontSize(Tokens.F_CAPTION)
          .backgroundColor(this.loginBusy ? Tokens.TEXT_TERTIARY : Tokens.MIST_TEAL)
          .fontColor('#FFFFFF')
          .borderRadius(Tokens.RADIUS_PILL)
          .enabled(!this.loginBusy)
          .onClick(() => {
            this.submitLogin();
          })
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.loginMsg.length > 0) {
        Text(this.loginMsg)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(this.loginOk ? Tokens.MIST_TEAL : Tokens.WARM_SAND)
          .width('100%')
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  entryCard() {
    Column() {
      Row() {
        Text('教务系统')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('系统浏览器')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Text(JwEntries.url())
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.SLATE_BLUE)
        .width('100%')
        .margin({ top: 6 })

      Text(JwLogic.loginHint())
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 4 })

      Button('打开教务系统')
        .width('100%')
        .height(44)
        .margin({ top: 10 })
        .backgroundColor(Tokens.MIST_TEAL)
        .fontColor('#FFFFFF')
        .borderRadius(Tokens.RADIUS_PILL)
        .onClick(() => {
          this.openJw();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  cardTile(card: JwCardDef) {
    Column() {
      Text(card.name)
        .fontSize(Tokens.F_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
      Text(card.hint)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .maxLines(2)
        .margin({ top: 4 })
      Text('在教务系统查看')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.SLATE_BLUE)
        .margin({ top: 6 })
    }
    .width('48%')
    .padding(12)
    .margin({ bottom: 8 })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.openJw();
    })
  }

  @State private headerFade: number = 0;

  build() {
    PageHeader({
      progress: this.headerFade,
      title: '教务',
      scroller: this.scroller,
      onBack: () => {
        this.onClose();
      }
    }) {
      Column() {
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll(this.scroller) {
            Column() {
              this.loginCard()

              this.entryCard()

          Row() {
            Text('课表速览')
              .fontSize(Tokens.F_LABEL)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
            Blank()
            Text(JwLogic.weekText(this.plan.week, this.plan.hasData))
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
          }
          .width('100%')
          .margin({ top: 14 })

          Column() {
            Text(this.todayText())
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
              .width('100%')
            if (this.plan.next !== undefined) {
              Text('下一节：' + JwLogic.nextText(this.plan.next.dayText, this.plan.next.dateText,
                this.plan.next.startText, this.plan.next.name))
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .width('100%')
                .margin({ top: 4 })
            }
            ForEach(this.todaySessions(), (session: SessionInfo) => {
              Row() {
                Text(session.startText + '–' + session.endText)
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_TERTIARY)
                  .width(96)
                Text(session.name)
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.TEXT_PRIMARY)
                  .layoutWeight(1)
                  .maxLines(1)
                if (session.room.length > 0) {
                  Text(session.room)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.TEXT_TERTIARY)
                }
              }
              .width('100%')
              .padding({ top: 4, bottom: 4 })
            }, (session: SessionInfo) => '' + session.startAt + '_' + session.name)
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .margin({ top: 8 })
          .backgroundColor(Tokens.CARD)
          .border({ width: 0.5, color: Tokens.CARD_EDGE })
          .borderRadius(Tokens.RADIUS_CARD)

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.WARM_SAND)
              .width('100%')
              .margin({ top: 8 })
          }

          Text('成绩 · 考试 · 选课 · 公告')
            .fontSize(Tokens.F_LABEL)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
            .width('100%')
            .margin({ top: 14 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(JwEntries.CARDS, (card: JwCardDef) => {
              Column() {
                this.cardTile(card)
              }
              .transition(Motion.listItem())
            }, (card: JwCardDef) => card.id)
          }
          .width('100%')
          .margin({ top: 8 })

          Text('HarmonyOS 端不保存教务账号密码；数据请在教务系统内查看。')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 4, bottom: 16 })
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .onDidScroll((offset: number) => {
            const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
            if (Math.abs(next - this.headerFade) > 0.03) {
              this.headerFade = next;
            }
          })
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          this.pullRefresh();
        })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 0 })
    }
  }

  private async pullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.load();
    this.refreshing = false;
  }
}
