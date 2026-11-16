import { Services } from '../../app/Services';
import { ClassMember, LeagueMember, MemberEntry } from '../../data/member/ClassMember';
import { MemberCategory, MemberCategoryBuilder, MemberCategoryCounts } from '../../data/member/MemberCategories';
import { ClassMembersResult } from '../../data/member/ClassMembersRepository';
import { ClassLeagueResult } from '../../data/member/ClassLeagueRepository';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';

/**
 * 名单工具（班委 / 团员 / 全班）。
 *
 * 隐私红线：页面只显示**座号 + 姓名 + 徽章**，不显示学号；不提供导出。
 */
@Component
export struct RosterScreen {
  onClose: () => void = () => {
  };

  @State private category: MemberCategory = MemberCategory.COMMITTEE;
  @State private classMembers: ClassMember[] = [];
  @State private leagueMembers: LeagueMember[] = [];
  @State private query: string = '';
  @State private loading: boolean = true;
  @State private errorMsg: string = '';

  aboutToAppear(): void {
    this.reload(false);
  }

  private async reload(force: boolean): Promise<void> {
    this.loading = true;
    this.errorMsg = '';
    const membersResult: ClassMembersResult = await Services.members.load(force);
    const leagueResult: ClassLeagueResult = await Services.league.load(force);
    this.classMembers = membersResult.members;
    this.leagueMembers = leagueResult.members;
    if (!membersResult.ok) {
      this.errorMsg = membersResult.message.length > 0 ? membersResult.message : '名单加载失败';
    }
    if (!leagueResult.ok && this.errorMsg.length === 0) {
      this.errorMsg = leagueResult.message.length > 0 ? leagueResult.message : '团员名单加载失败';
    }
    this.loading = false;
  }

  private counts(): MemberCategoryCounts {
    return MemberCategoryBuilder.counts(this.classMembers, this.leagueMembers);
  }

  private entries(): MemberEntry[] {
    return MemberCategoryBuilder.visibleEntries(this.category, this.classMembers, this.leagueMembers, this.query);
  }

  private categories(): MemberCategory[] {
    return [MemberCategory.COMMITTEE, MemberCategory.LEAGUE, MemberCategory.ALL];
  }

  private countOf(category: MemberCategory): number {
    return this.counts().of(category);
  }

  @Builder
  categoryTab(category: MemberCategory) {
    Row({ space: 6 }) {
      Text(category)
        .fontSize(Tokens.F_LABEL)
        .fontWeight(this.category === category ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.category === category ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      Text('' + this.countOf(category))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(this.category === category ? '#E8F2EF' : Tokens.TEXT_TERTIARY)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(this.category === category ? Tokens.MIST_TEAL : Tokens.CARD)
    .borderRadius(Tokens.RADIUS_PILL)
    .onClick(() => {
      this.category = category;
    })
  }

  @Builder
  memberRow(entry: MemberEntry) {
    Row() {
      Text('' + entry.seat)
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width(36)
        .height(36)
        .textAlign(TextAlign.Center)
        .backgroundColor(Tokens.BG)
        .borderRadius(10)

      Text(entry.name)
        .fontSize(Tokens.F_BODY)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
        .margin({ left: 12 })

      if (entry.badge.length > 0) {
        Text(entry.badge)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(Tokens.TINT_TEAL)
          .borderRadius(Tokens.RADIUS_PILL)
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
  }

  build() {
    Column() {
      PageHeader({
        title: '名单',
        actionText: this.loading ? '' : '刷新',
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.reload(true);
        }
      })

      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
          Text('加载名单…').fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_TERTIARY)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMsg.length > 0) {
        Column({ space: 12 }) {
          Text(this.errorMsg)
            .fontSize(Tokens.F_BODY)
            .fontColor(Tokens.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
          Button('重试')
            .backgroundColor(Tokens.MIST_TEAL)
            .fontColor('#FFFFFF')
            .height(40)
            .borderRadius(Tokens.RADIUS_PILL)
            .onClick(() => {
              this.reload(true);
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(Tokens.PAGE_PADDING)
      } else {
        Row({ space: 8 }) {
          ForEach(this.categories(), (category: MemberCategory) => {
            this.categoryTab(category)
          }, (category: MemberCategory) => category)
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })

        TextInput({ placeholder: '搜索姓名', text: this.query })
          .height(40)
          .margin({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 10 })
          .backgroundColor(Tokens.CARD)
          .borderRadius(Tokens.RADIUS_INPUT)
          .fontSize(Tokens.F_LABEL)
          .onChange((value: string) => {
            this.query = value;
          })

        if (this.entries().length === 0) {
          Column() {
            Text(this.query.length > 0 ? '没有匹配的姓名' : '暂无数据')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.TEXT_TERTIARY)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.entries(), (entry: MemberEntry) => {
              ListItem() {
                this.memberRow(entry)
              }
            }, (entry: MemberEntry) => '' + entry.seat)
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 8 })
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
          .backgroundColor(Tokens.CARD)
          .borderRadius(Tokens.RADIUS_CARD)
          .clip(true)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Tokens.BG)
  }
}
