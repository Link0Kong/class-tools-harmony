import { ClassMember } from '../../data/member/ClassMember';
import { MemberCategory, MemberCategoryBuilder } from '../../data/member/MemberCategories';
import { Tokens } from '../theme/Tokens';
import { RosterSearchBox } from './RosterSearchBox';

@Component
export struct RosterPicker {
  @Prop members: ClassMember[] = [];
  @Prop leagueSeats: number[] = [];
  @Prop selected: number[] = [];
  onSelect: (seats: number[]) => void = () => {};
  @State private category: MemberCategory = MemberCategory.ALL;
  @State private query: string = '';
  @State private matches: number[] = [];

  private visible(): ClassMember[] {
    return MemberCategoryBuilder.matchingMembers(this.category, this.members, this.leagueSeats, this.query, this.matches);
  }

  @Builder
  scopeTab(scope: MemberCategory) {
    Text(scope)
      .fontSize(Tokens.F_LABEL).fontWeight(FontWeight.Medium)
      .fontColor(this.category === scope ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.category === scope ? '#356C61' : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .onClick(() => { this.category = scope; })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.scopeTab(MemberCategory.ALL)
        this.scopeTab(MemberCategory.COMMITTEE)
        this.scopeTab(MemberCategory.LEAGUE)
      }.width('100%')
      RosterSearchBox({ onFilter: (text: string, seats: number[]) => { this.query = text; this.matches = seats; } })
      Row({ space: 12 }) {
        Button('只选筛选结果', { type: ButtonType.Capsule })
          .fontSize(Tokens.F_CAPTION).fontColor('#285E54').backgroundColor(Tokens.TINT_TEAL)
          .height(32).enabled(this.visible().length > 0)
          .onClick(() => { this.onSelect(this.visible().map((member: ClassMember) => member.seat)); })
        Text('清空').fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY)
          .padding({ top: 8, bottom: 8 }).onClick(() => { this.onSelect([]); })
        Blank()
        Text('已选 ' + this.selected.length + ' 人').fontSize(Tokens.F_CAPTION).fontColor(Tokens.TEXT_SECONDARY)
      }.width('100%')
      if (this.visible().length === 0) {
        Text('没有匹配的成员').fontSize(Tokens.F_LABEL).fontColor(Tokens.TEXT_SECONDARY).margin({ top: 6 })
      }
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.visible(), (m: ClassMember) => {
          Text(m.seat + ' ' + m.name)
            .fontSize(Tokens.F_LABEL)
            .fontColor(this.selected.includes(m.seat) ? '#255A50' : Tokens.TEXT_SECONDARY)
            .backgroundColor(this.selected.includes(m.seat) ? Tokens.TINT_TEAL : Tokens.CONTROL)
            .border({ width: 1, color: this.selected.includes(m.seat) ? '#7AA798' : Tokens.CARD_EDGE })
            .padding({ left: 10, right: 10, top: 8, bottom: 8 }).borderRadius(10)
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              this.onSelect(this.selected.includes(m.seat) ?
                this.selected.filter((seat: number) => seat !== m.seat) : this.selected.concat([m.seat]));
            })
        }, (m: ClassMember) => m.seat + '_' + this.selected.includes(m.seat) + '_' + m.name)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
