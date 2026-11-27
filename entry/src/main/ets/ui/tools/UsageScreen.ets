import { Tokens } from '../theme/Tokens';
import { PageInsets } from '../theme/PageInsets';
import { AppSymbols } from '../theme/AppSymbols';
import { PageHeader } from '../components/PageHeader';
import { UsageCard, UsageCategory, UsageData } from '../../features/usage/UsageData';

/** 使用说明：与网页端一致的卡片轮播 + 分类 + 一键总览。 */
@Component
export struct UsageScreen {
  onClose: () => void = () => {
  };

  @State private cat: string = 'start';
  @State private index: number = 0;
  @State private overview: boolean = false;
  @State private catFade: number = 1;
  @State private catShift: number = 0;
  @State private iconBob: number = 0;

  aboutToAppear(): void {
    setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 1800,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.iconBob = -4;
      });
    }, 40);
  }

  private cards(): UsageCard[] {
    return UsageData.CARDS;
  }

  private currentCard(): UsageCard {
    const list: UsageCard[] = this.cards();
    if (list.length === 0) {
      return UsageData.CARDS[0];
    }
    const at: number = this.index < 0 ? 0 : (this.index >= list.length ? list.length - 1 : this.index);
    return list[at];
  }

  private catStart(cat: string): number {
    const list: UsageCard[] = UsageData.ofCategory(cat);
    if (list.length === 0) {
      return 0;
    }
    return this.indexOfGlobal(list[0].id);
  }

  private localIndex(): number {
    const card: UsageCard = this.currentCard();
    return this.index - this.catStart(card.cat) + 1;
  }

  private localTotal(): number {
    return UsageData.ofCategory(this.currentCard().cat).length;
  }

  private indexOfGlobal(id: string): number {
    for (let i = 0; i < UsageData.CARDS.length; i++) {
      if (UsageData.CARDS[i].id === id) {
        return i;
      }
    }
    return 0;
  }

  private toneBg(tone: string): string {
    if (tone === 'blue') {
      return '#EDF2F7';
    }
    if (tone === 'mint') {
      return '#EAF2EC';
    }
    if (tone === 'sand') {
      return '#FAF3E6';
    }
    if (tone === 'violet') {
      return '#F1EEF7';
    }
    if (tone === 'rose') {
      return '#F7EDEB';
    }
    return '#F0F2F1';
  }

  private toneFg(tone: string): string {
    if (tone === 'blue') {
      return '#4E6D8C';
    }
    if (tone === 'mint') {
      return '#3F6F66';
    }
    if (tone === 'sand') {
      return '#8A643B';
    }
    if (tone === 'violet') {
      return '#66579A';
    }
    if (tone === 'rose') {
      return '#9C5147';
    }
    return '#5F6A61';
  }

  private symbolOf(card: UsageCard): Resource {
    return AppSymbols.usage(card.id);
  }

  private go(delta: number): void {
    const count: number = this.cards().length;
    if (count <= 0) {
      return;
    }
    let next: number = this.index + delta;
    if (next < 0) {
      next = 0;
    }
    if (next > count - 1) {
      next = count - 1;
    }
    this.index = next;
    this.cat = this.currentCard().cat;
  }

  private pickCat(key: string): void {
    const target: number = this.catStart(key);
    if (key === this.cat && target === this.index) {
      return;
    }
    const ui = this.getUIContext();
    ui.animateTo({ duration: 130, curve: Curve.EaseIn }, () => {
      this.catFade = 0;
      this.catShift = -14;
    });
    setTimeout(() => {
      this.cat = key;
      this.index = target;
      ui.animateTo({ duration: 280, curve: Curve.FastOutSlowIn }, () => {
        this.catFade = 1;
        this.catShift = 0;
      });
    }, 140);
  }

  private jumpTo(card: UsageCard): void {
    this.cat = card.cat;
    this.catFade = 1;
    this.catShift = 0;
    this.index = this.indexOfGlobal(card.id);
    this.overview = false;
  }

  private previewKind(id: string): string {
    if (id === 'id') {
      return 'badge';
    }
    if (id === 'nav') {
      return 'grid';
    }
    if (id === 'draw' || id === 'roll') {
      return 'draw';
    }
    if (id === 'roster') {
      return 'people';
    }
    if (id === 'tt') {
      return 'grid';
    }
    if (id === 'hw' || id === 'jw') {
      return 'list';
    }
    if (id === 'nt' || id === 'fb') {
      return 'chat';
    }
    if (id === 'ft' || id === 'stats' || id === 'vote') {
      return 'bars';
    }
    if (id === 'power' || id === 'water') {
      return 'meter';
    }
    if (id === 'file') {
      return 'files';
    }
    if (id === 'diag') {
      return 'health';
    }
    return 'list';
  }

  @Builder
  previewCell(color: string, height: number) {
    Row()
      .layoutWeight(1)
      .height(height)
      .borderRadius(4)
      .backgroundColor(color)
  }

  @Builder
  previewBody(card: UsageCard) {
    if (this.previewKind(card.id) === 'badge') {
      Column() {
        Row() {
          Circle()
            .width(32)
            .height(32)
            .fill(Tokens.tint(this.toneFg(card.tone), 0.22))
          Column({ space: 4 }) {
            Row()
              .width(50)
              .height(5)
              .borderRadius(2.5)
              .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.58))
            Row()
              .width(34)
              .height(4)
              .borderRadius(2)
              .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.26))
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 8 })
        }
        .width('100%')

        Row()
          .width('100%')
          .height(18)
          .borderRadius(6)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.15))
          .margin({ top: 10 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'grid') {
      Column({ space: 4 }) {
        Row({ space: 4 }) {
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.42), 15)
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.16), 15)
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.16), 15)
        }
        .width('100%')
        Row({ space: 4 }) {
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.16), 15)
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.34), 15)
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.16), 15)
        }
        .width('100%')
        Row({ space: 4 }) {
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.16), 15)
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.16), 15)
          this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.42), 15)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'draw') {
      Row({ space: 4 }) {
        this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.45), 22)
        this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.24), 22)
        this.previewCell(Tokens.tint(this.toneFg(card.tone), 0.24), 22)
      }
      .width('100%')
      Row({ space: 6 }) {
        Row()
          .layoutWeight(1)
          .height(32)
          .borderRadius(8)
          .border({ width: 1, color: Tokens.tint(this.toneFg(card.tone), 0.30) })
        Row()
          .width(42)
          .height(32)
          .borderRadius(8)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.55))
      }
      .width('100%')
      .margin({ top: 8 })
    } else if (this.previewKind(card.id) === 'people') {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Circle().width(22).height(22).fill(Tokens.tint(this.toneFg(card.tone), 0.45))
          Circle().width(22).height(22).fill(Tokens.tint(this.toneFg(card.tone), 0.24))
          Circle().width(22).height(22).fill(Tokens.tint(this.toneFg(card.tone), 0.24))
          Circle().width(22).height(22).fill(Tokens.tint(this.toneFg(card.tone), 0.14))
        }
        .width('100%')
        Row()
          .width('100%')
          .height(5)
          .borderRadius(2.5)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.18))
        Row()
          .width('70%')
          .height(5)
          .borderRadius(2.5)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.12))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'chat') {
      Column({ space: 8 }) {
        Row()
          .width('72%')
          .height(16)
          .borderRadius(6)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.22))
        Row()
          .width('58%')
          .height(16)
          .borderRadius(6)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.45))
          .margin({ left: '38%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'bars') {
      Row({ space: 6 }) {
        Row().width(10).height(20).borderRadius(3).backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.22))
        Row().width(10).height(34).borderRadius(3).backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.45))
        Row().width(10).height(25).borderRadius(3).backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.30))
        Row().width(10).height(42).borderRadius(3).backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.62))
        Row().width(10).height(30).borderRadius(3).backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.34))
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Bottom)
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'meter') {
      Column() {
        Row() {
          Text('234.7')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.toneFg(card.tone))
          Text('度')
            .fontSize(10)
            .fontColor(Tokens.tint(this.toneFg(card.tone), 0.65))
            .margin({ left: 4, bottom: 2 })
        }
        .alignItems(VerticalAlign.Bottom)
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(7).borderRadius(3.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.16))
          Row().width('64%').height(7).borderRadius(3.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.55))
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'files') {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Row().width('80%').height(4).borderRadius(2)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.40))
          Row().width('55%').height(4).borderRadius(2)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.20))
        }
        .width(38)
        .height(46)
        .padding(8)
        .borderRadius(7)
        .border({ width: 1, color: Tokens.tint(this.toneFg(card.tone), 0.28) })

        Column({ space: 4 }) {
          Row().width('80%').height(4).borderRadius(2)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.40))
          Row().width('55%').height(4).borderRadius(2)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.20))
        }
        .width(38)
        .height(46)
        .padding(8)
        .borderRadius(7)
        .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.12))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.previewKind(card.id) === 'health') {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Circle().width(9).height(9).fill(this.toneFg(card.tone))
          Row().layoutWeight(1).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.30))
          Row().width(22).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.55))
        }
        .width('100%')
        Row({ space: 6 }) {
          Circle().width(9).height(9).fill(Tokens.tint(this.toneFg(card.tone), 0.45))
          Row().layoutWeight(1).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.20))
          Row().width(22).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.35))
        }
        .width('100%')
        Row({ space: 6 }) {
          Circle().width(9).height(9).fill(Tokens.tint(this.toneFg(card.tone), 0.45))
          Row().layoutWeight(1).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.20))
          Row().width(22).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.35))
        }
        .width('100%')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Circle().width(10).height(10).fill(Tokens.tint(this.toneFg(card.tone), 0.50))
          Row().layoutWeight(1).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.30))
        }
        .width('100%')
        Row({ space: 6 }) {
          Circle().width(10).height(10).fill(Tokens.tint(this.toneFg(card.tone), 0.24))
          Row().layoutWeight(1).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.18))
        }
        .width('100%')
        Row({ space: 6 }) {
          Circle().width(10).height(10).fill(Tokens.tint(this.toneFg(card.tone), 0.24))
          Row().layoutWeight(1).height(5).borderRadius(2.5)
            .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.18))
        }
        .width('100%')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  usageIcon(card: UsageCard) {
    Column() {
      Row({ space: 4 }) {
        Circle().width(4).height(4).fill(Tokens.tint(this.toneFg(card.tone), 0.45))
        Circle().width(4).height(4).fill(Tokens.tint(this.toneFg(card.tone), 0.28))
        Circle().width(4).height(4).fill(Tokens.tint(this.toneFg(card.tone), 0.18))
        Blank()
        Row()
          .width(18)
          .height(4)
          .borderRadius(2)
          .backgroundColor(Tokens.tint(this.toneFg(card.tone), 0.18))
      }
      .width('100%')

      this.previewBody(card)
    }
    .width(184)
    .height(116)
    .padding({ left: 10, right: 10, top: 8, bottom: 10 })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(16)
    .border({ width: 1, color: Tokens.tint(this.toneFg(card.tone), 0.18) })
    .shadow({
      radius: 18,
      color: Tokens.tint(this.toneFg(card.tone), 0.18),
      offsetX: 0,
      offsetY: 8
    })
    .translate({ y: this.iconBob })
  }

  @Builder
  usageCard(card: UsageCard) {
    Scroll() {
      Column() {
        Row() {
          Text(UsageData.labelOf(card.cat))
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.toneFg(card.tone))
            .backgroundColor(this.toneBg(card.tone))
            .borderRadius(Tokens.RADIUS_PILL)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          Blank()
          Text(this.localIndex() + ' / ' + this.localTotal())
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
        .width('100%')

        Stack() {
          this.usageIcon(card)
        }
        .width('100%')
        .height(132)
        .margin({ top: 4 })

        Text(card.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 14 })
        Text(card.sub)
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 6 })

        Column() {
          ForEach(card.steps, (step: string, i: number) => {
            Row() {
              Text('' + (i + 1))
                .fontSize(Tokens.F_CAPTION)
                .fontColor('#FFFFFF')
                .width(20)
                .height(20)
                .textAlign(TextAlign.Center)
                .backgroundColor(Tokens.MIST_TEAL)
                .borderRadius(10)
              Text(step)
                .fontSize(Tokens.F_BODY)
                .fontColor(Tokens.TEXT_PRIMARY)
                .layoutWeight(1)
                .margin({ left: 10 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ top: 8, bottom: 8 })
          }, (step: string, i: number) => card.id + '_s' + i)
        }
        .width('100%')
        .margin({ top: 12 })

        Row() {
          Text('提示')
            .fontSize(Tokens.F_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.toneFg(card.tone))
            .margin({ right: 8 })
          Text(card.tip)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding(12)
        .backgroundColor(this.toneBg(card.tone))
        .borderRadius(12)
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: PageInsets.HORIZONTAL, right: PageInsets.HORIZONTAL,
        top: Tokens.GAP_LG, bottom: Tokens.SPACE_20 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .onDidScroll((offset: number) => {
      const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
      if (Math.abs(next - this.headerFade) > 0.03) {
        this.headerFade = next;
      }
    })
  }

  @Builder
  overviewPanel() {
    Column() {
      Row() {
        Text('全部使用说明')
          .fontSize(Tokens.F_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('关闭')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: 10, right: 6, top: 8, bottom: 8 })
          .onClick(() => {
            this.overview = false;
          })
      }
      .width('100%')
      .padding({ bottom: 6 })

      Text('共 ' + UsageData.CARDS.length + ' 张卡片 · 点条目直接跳到对应卡片')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ bottom: 8 })

      Scroll() {
        Column() {
          ForEach(UsageData.CATEGORIES, (cat: UsageCategory, ci: number) => {
            Column() {
              Text(cat.label)
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Medium)
                .fontColor(Tokens.TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 8, bottom: 4 })
              ForEach(UsageData.ofCategory(cat.key), (card: UsageCard, i: number) => {
                Row() {
                  Stack({ alignContent: Alignment.Center }) {
                    SymbolGlyph(this.symbolOf(card))
                      .fontSize(19)
                      .fontWeight(FontWeight.Medium)
                      .fontColor([this.toneFg(card.tone)])
                      .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
                  }
                  .width(34)
                  .height(34)
                  .backgroundColor(this.toneBg(card.tone))
                  .borderRadius(9)
                  Column() {
                    Text(card.title)
                      .fontSize(Tokens.F_BODY)
                      .fontColor(Tokens.TEXT_PRIMARY)
                    Text(card.sub)
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.TEXT_TERTIARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 10 })
                  SymbolGlyph($r('sys.symbol.arrow_right'))
                    .fontSize(16)
                    .fontColor([Tokens.TEXT_TERTIARY])
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
                .onClick(() => {
                  this.jumpTo(card);
                })
              }, (card: UsageCard, i: number) => 'ov_' + card.id)
            }
            .width('100%')
          }, (cat: UsageCategory, ci: number) => 'ovc_' + cat.key)
          Blank().height(20)
        }
        .width('100%')
      }
      .layoutWeight(1)
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
    .height('78%')
    .padding({ left: PageInsets.HORIZONTAL, right: PageInsets.HORIZONTAL, top: Tokens.GAP_LG })
    .backgroundColor(Tokens.SHEET)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius({ topLeft: Tokens.RADIUS_FLOAT, topRight: Tokens.RADIUS_FLOAT })
  }

  @State private headerFade: number = 0;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      PageHeader({
      progress: this.headerFade,
        title: '使用说明',
        actionText: '一键总览',
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.overview = true;
        }
      }) {
        Column() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(UsageData.CATEGORIES, (cat: UsageCategory, i: number) => {
            Text(cat.label)
              .fontSize(Tokens.F_LABEL)
              .fontColor(this.cat === cat.key ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
              .backgroundColor(this.cat === cat.key ? Tokens.MIST_TEAL : Tokens.CONTROL)
              .border({ width: 1, color: this.cat === cat.key ? Tokens.MIST_TEAL : Tokens.DIVIDER })
              .borderRadius(Tokens.RADIUS_PILL)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.pickCat(cat.key);
              })
          }, (cat: UsageCategory, i: number) => 'uc_' + cat.key)
        }
        .width('100%')
        .padding({ left: PageInsets.HORIZONTAL, right: PageInsets.HORIZONTAL, top: Tokens.GAP_SM })

        Swiper() {
          ForEach(this.cards(), (card: UsageCard, i: number) => {
            Column() {
              this.usageCard(card)
            }
            .width('100%')
            .height('100%')
          }, (card: UsageCard, i: number) => 'ugc_' + card.id)
        }
        .width('100%')
        .layoutWeight(1)
        .index(this.index)
        .loop(false)
        .indicator(false)
        .duration(320)
        .opacity(this.catFade)
        .translate({ x: this.catShift })
        .onChange((index: number) => {
          this.index = index;
          this.cat = this.currentCard().cat;
        })

        Row({ space: Tokens.GAP_LG }) {
          Text('‹ 上一张')
            .fontSize(Tokens.F_LABEL)
            .fontColor(this.index <= 0 ? Tokens.TEXT_TERTIARY : Tokens.SLATE_BLUE)
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .onClick(() => {
              this.go(-1);
            })
          Text(this.localIndex() + ' / ' + this.localTotal())
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
          Text('下一张 ›')
            .fontSize(Tokens.F_LABEL)
            .fontColor(this.index >= this.cards().length - 1 ? Tokens.TEXT_TERTIARY : Tokens.SLATE_BLUE)
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .onClick(() => {
              this.go(1);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ bottom: Tokens.GAP_SM })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 0 })
      }

      if (this.overview) {
        Column() {
          this.overviewPanel()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .backgroundColor(Tokens.SCRIM)
        .onClick(() => {
          this.overview = false;
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
