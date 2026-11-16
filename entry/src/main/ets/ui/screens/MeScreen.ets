import { CloudConfig } from '../../config/CloudConfig';
import { Tokens } from '../theme/Tokens';
import { common } from '@kit.AbilityKit';
import { HuaweiAccount } from '../../data/account/HuaweiAccount';
import { AccountBindingRepository, BindItem } from '../../data/account/AccountBindingRepository';
import { BrandMark } from '../components/BrandMark';
import { Services } from '../../app/Services';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import { NickLogic } from '../../features/home/NickLogic';
import { AppPush } from '../../features/push/AppPush';

/** 我的：身份卡 + 设置项 + 退出登录。 */
@Component
export struct MeScreen {
  @Prop userName: string = '';
  @Prop maskedSid: string = '';
  @Prop roleLabel: string = '';
  @Prop isAdmin: boolean = false;
  @Prop syncState: string = '';
  onSyncNow: () => void = () => {
  };
  onLogout: () => void = () => {
  };

  @State private nick: string = '';
  @State private nickEditing: boolean = false;
  @State private nickDraft: string = '';
  @State private nickNotice: string = '';
  @State private pushOn: boolean = false;
  @State private pushBusy: boolean = false;
  @State private pushNotice: string = '';
  @State private hwItems: BindItem[] = [];
  @State private hwBusy: boolean = false;
  @State private hwNotice: string = '';

  aboutToAppear(): void {
    const sections: Blob = Services.userdata.currentSections();
    const value = sections['nick'];
    this.nick = value === undefined ? '' : String(value);
    this.pushOn = AppPush.enabled();
    this.loadBindings();
  }

  private async loadBindings(): Promise<void> {
    this.hwItems = await AccountBindingRepository.list();
  }

  private async bindHuawei(): Promise<void> {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    this.hwNotice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const openId: string = await HuaweiAccount.openId(context);
      const err: string = await AccountBindingRepository.bind(openId, 'phone');
      this.hwNotice = err.length > 0 ? err : '已绑定当前华为账号';
      await this.loadBindings();
    } catch (e) {
      this.hwNotice = HuaweiAccount.message(e as Object);
    }
    this.hwBusy = false;
  }

  private async unbindHuawei(openId: string): Promise<void> {
    if (this.hwBusy) {
      return;
    }
    this.hwBusy = true;
    const ok: boolean = await AccountBindingRepository.unbind(openId);
    this.hwNotice = ok ? '已解绑' : '解绑失败';
    await this.loadBindings();
    this.hwBusy = false;
  }

  private async togglePush(next: boolean): Promise<void> {
    if (this.pushBusy) {
      return;
    }
    this.pushBusy = true;
    this.pushOn = next;
    if (next) {
      const ok: boolean = await AppPush.register();
      this.pushNotice = ok ? '已开启系统推送' : '推送开通失败，请确认已开通推送服务';
      if (!ok) {
        this.pushOn = false;
      }
    } else {
      await AppPush.disable();
      this.pushNotice = '已关闭系统推送';
    }
    this.pushBusy = false;
  }

  private async saveNick(): Promise<void> {
    const next: string = NickLogic.normalize(this.nickDraft);
    const sections: Blob = Services.userdata.currentSections();
    sections['nick'] = next;
    await Services.userdata.updateCurrent(sections);
    const keys: Set<string> = new Set<string>();
    keys.add('nick');
    const result = await Services.userdata.push(false, keys);
    this.nick = next;
    this.nickEditing = false;
    this.nickNotice = result.ok() ? '昵称已保存并同步' : '已保存到本机，稍后自动同步';
  }

  @Builder
  row(title: string, value: string, danger: boolean) {
    Row() {
      Text(title)
        .fontSize(Tokens.F_BODY)
        .fontColor(danger ? Tokens.DANGER : Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
      Text(value)
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_TERTIARY)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
  }

  build() {
    Scroll() {
      Column() {
        Text('我的')
          .fontSize(Tokens.F_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 24, bottom: 18 })

        Column() {
          Row() {
            Text(this.userName.length > 0 ? this.userName.substring(0, 1) : '?')
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor(Tokens.MIST_TEAL)
              .width(56)
              .height(56)
              .textAlign(TextAlign.Center)
              .backgroundColor(Tokens.TINT_TEAL)
              .borderRadius(28)

            Column() {
              Row() {
                Text(this.userName)
                  .fontSize(Tokens.F_HEADING)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Tokens.TEXT_PRIMARY)
                if (this.roleLabel.length > 0) {
                  Text(this.roleLabel)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.MIST_TEAL)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(Tokens.TINT_TEAL)
                    .borderRadius(Tokens.RADIUS_PILL)
                    .margin({ left: 8 })
                }
              }

              Text('学号 ' + this.maskedSid + (this.isAdmin ? ' · 管理员' : ''))
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 14 })
          }
          .width('100%')
          .padding(16)
        }
        .width('100%')
        .backgroundColor(Tokens.CARD)
        .borderRadius(Tokens.RADIUS_CARD)

        Column() {
          Row() {
            Text('云同步')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .layoutWeight(1)
            Text(this.syncState.length > 0 ? this.syncState : '未同步')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.TEXT_TERTIARY)
            Text('立即同步')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.MIST_TEAL)
              .margin({ left: 14 })
              .onClick(() => {
                this.onSyncNow();
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          Row() {
            Text('昵称')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.TEXT_PRIMARY)
              .layoutWeight(1)
            Text(this.nick.length > 0 ? this.nick : '未设置')
              .fontSize(Tokens.F_LABEL)
              .fontColor(this.nick.length > 0 ? Tokens.TEXT_SECONDARY : Tokens.TEXT_TERTIARY)
            Text(this.nickEditing ? '取消' : '编辑')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.MIST_TEAL)
              .margin({ left: 14 })
              .onClick(() => {
                this.nickEditing = !this.nickEditing;
                this.nickDraft = this.nick;
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })

          if (this.nickEditing) {
            Row({ space: 10 }) {
              TextInput({ text: this.nickDraft, placeholder: '昵称（≤16 字，可留空清除）' })
                .layoutWeight(1)
                .height(40)
                .backgroundColor(Tokens.BG)
                .fontSize(Tokens.F_CAPTION)
                .borderRadius(8)
                .onChange((value: string) => {
                  this.nickDraft = value;
                })
              Button('保存')
                .height(36)
                .fontSize(Tokens.F_CAPTION)
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.saveNick();
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 12 })
          }
          if (this.nickNotice.length > 0) {
            Text(this.nickNotice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 10 })
          }
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.row('通知与提醒', '「通知」工具', false)
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          Row() {
            Column() {
              Text('消息推送')
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_PRIMARY)
              Text('新通知/作业到达时由系统推送')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.pushOn })
              .selectedColor(Tokens.MIST_TEAL)
              .enabled(!this.pushBusy)
              .onChange((isOn: boolean) => {
                this.togglePush(isOn);
              })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          if (this.pushNotice.length > 0) {
            Text(this.pushNotice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 10 })
          }
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          Row() {
            Column() {
              Text('华为账号')
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_PRIMARY)
              Text('绑定后手表可免学号登录，最多 3 个')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button(this.hwBusy ? '处理中…' : '绑定')
              .height(30)
              .fontSize(13)
              .backgroundColor(Tokens.MIST_TEAL)
              .fontColor('#FFFFFF')
              .borderRadius(15)
              .enabled(!this.hwBusy)
              .onClick(() => {
                this.bindHuawei();
              })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          ForEach(this.hwItems, (item: BindItem) => {
            Row() {
              Text(item.masked())
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_SECONDARY)
                .layoutWeight(1)
              Text('解绑')
                .fontSize(12)
                .fontColor(Tokens.TEXT_TERTIARY)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .onClick(() => {
                  this.unbindHuawei(item.openId);
                })
            }
            .width('100%')
            .height(34)
            .padding({ left: 16, right: 16 })
          }, (item: BindItem) => item.openId)
          if (this.hwNotice.length > 0) {
            Text(this.hwNotice)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 10 })
          }
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.row('诊断', '「诊断」工具', false)
          Divider().color(Tokens.DIVIDER).strokeWidth(0.5).margin({ left: 16, right: 16 })
          this.row('使用说明', 'docs/ACCEPTANCE.md', false)
        }
        .width('100%')
        .margin({ top: 14 })
        .backgroundColor(Tokens.CARD)
        .borderRadius(Tokens.RADIUS_CARD)

        Column() {
          Row() {
            Text('退出登录')
              .fontSize(Tokens.F_BODY)
              .fontColor(Tokens.DANGER)
          }
          .width('100%')
          .height(52)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onLogout();
          })
        }
        .width('100%')
        .margin({ top: 14 })
        .backgroundColor(Tokens.CARD)
        .borderRadius(Tokens.RADIUS_CARD)

        Row() {
          BrandMark({ markSize: 16 })
          Text('班级工具站 · HarmonyOS ' + CloudConfig.APP_VERSION)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 24, bottom: 12 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 720 })
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .backgroundColor(Tokens.BG)
  }
}
