import { RosterSearchBox } from '../components/RosterSearchBox';
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

  @State private category: MemberCategory = MemberCategory.ALL;
  @State private classMembers: ClassMember[] = [];
  @State private leagueMembers: LeagueMember[] = [];
  @State private query: string = '';
  @State private matchedSeats: number[] = [];
  @State private loading: boolean = true;
  @State private refreshing: boolean = false;
  @State private errorMsg: string = '';
  @State private leagueError: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload(false);
  }

  private async reload(force: boolean, quiet: boolean = false): Promise<void> {
    if (!quiet) {
      this.loading = true;
    }
    this.errorMsg = '';
    const membersResult: ClassMembersResult = await Services.members.load(force);
    const leagueResult: ClassLeagueResult = await Services.league.load(force);
    this.classMembers = membersResult.members;
    this.leagueMembers = leagueResult.members;
    if (!membersResult.ok) {
      this.errorMsg = membersResult.message.length > 0 ? membersResult.message : '名单加载失败';
    }
    this.leagueError = leagueResult.ok ? '' : (leagueResult.message || '团员名单加载失败');
    this.loading = false;
  }

  private counts(): MemberCategoryCounts {
    return MemberCategoryBuilder.counts(this.classMembers, this.leagueMembers);
  }

  private entries(): MemberEntry[] {
    return MemberCategoryBuilder.visibleEntries(this.category, this.classMembers, this.leagueMembers, this.query, this.matchedSeats);
  }

  private categories(): MemberCategory[] {
    return [MemberCategory.ALL, MemberCategory.COMMITTEE, MemberCategory.LEAGUE];
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
    .backgroundColor(this.category === category ? Tokens.MIST_TEAL : Tokens.CONTROL)
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
        .backgroundColor(Tokens.CONTROL)
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
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(Tokens.TINT_TEAL)
          .borderRadius(Tokens.RADIUS_PILL)
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 12, right: 12 })
  }

  @State private headerFade: number = 0;

  build() {
    PageHeader({
      progress: this.headerFade,
      title: '名单',
      scroller: this.scroller,
      onBack: () => {
        this.onClose();
      }
    }) {
      Column() {
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

          Row() {
            RosterSearchBox({ onFilter: (text: string, seats: number[]) => {
              this.query = text;
              this.matchedSeats = seats;
            } })
          }.padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 10 })

          if (this.entries().length === 0) {
            Column() {
              Text(this.category === MemberCategory.LEAGUE && this.leagueError ? this.leagueError :
                (this.query.length > 0 ? '没有匹配的成员' : '暂无数据'))
                .fontSize(Tokens.F_LABEL)
                .fontColor(Tokens.TEXT_TERTIARY)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
              List({ scroller: this.scroller }) {
                ForEach(this.entries(), (entry: MemberEntry) => {
                  ListItem() {
                    this.memberRow(entry)
                  }
                }, (entry: MemberEntry) => '' + entry.seat)
              }
              .width('100%')
              .height('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
              .backgroundColor(Tokens.CARD)
              .border({ width: 0.5, color: Tokens.CARD_EDGE })
              .borderRadius(Tokens.RADIUS_CARD)
              .clip(true)
              .scrollBar(BarState.Off)
              .onDidScroll((offset: number) => {
                const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
                if (Math.abs(next - this.headerFade) > 0.03) {
                  this.headerFade = next;
                }
              })
            }
            .layoutWeight(1)
            .margin({ top: 8 })
            .onRefreshing(() => {
              this.pullRefresh();
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 0 })
    }
  }

  private async pullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.reload(true, true);
    this.refreshing = false;
  }
}
