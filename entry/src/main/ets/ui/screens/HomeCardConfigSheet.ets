import { HomeCardConfig, HomeCardDef, HomeCards } from '../../data/home/HomeCards';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { AppSymbols } from '../theme/AppSymbols';

/**
 * 工作台卡片面板：只负责卡片的添加 / 移除 / 恢复默认。
 * 排序与缩放不在面板里操作：
 * - 排序：在工作台长按卡片拖动；
 * - 缩放：拖动卡片右下角加粗的边框线抓手，在半宽 / 整行间切换。
 */
@Component
export struct HomeCardConfigSheet {
  @Prop cards: HomeCardConfig[] = [];
  onAddCard: (id: string) => void = () => {
  };
  onRemoveCard: (id: string) => void = () => {
  };
  onReset: () => void = () => {
  };
  onDone: () => void = () => {
  };

  private titleOf(id: string): string {
    const def: HomeCardDef | undefined = HomeCards.byId(id);
    return def !== undefined ? def.title : id;
  }

  private subtitleOf(id: string): string {
    const def: HomeCardDef | undefined = HomeCards.byId(id);
    return def !== undefined ? def.subtitle : '';
  }

  private symbolOf(id: string): Resource {
    const def: HomeCardDef | undefined = HomeCards.byId(id);
    return def !== undefined ? def.symbol : AppSymbols.INFO;
  }

  private accentOf(id: string): string {
    const def: HomeCardDef | undefined = HomeCards.byId(id);
    return def !== undefined ? def.accent : Tokens.MIST_TEAL;
  }

  @Builder
  removeButton(onTap: () => void) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(AppSymbols.MINUS)
        .fontSize(16)
        .fontColor([Tokens.DANGER])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width(36)
    .height(36)
    .borderRadius(10)
    .backgroundColor(Tokens.CONTROL_SOFT)
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  cardRow(cfg: HomeCardConfig) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.symbolOf(cfg.id))
          .fontSize(20)
          .fontColor([this.accentOf(cfg.id)])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      }
      .width(38)
      .height(38)
      .borderRadius(12)
      .backgroundColor(Tokens.tint(this.accentOf(cfg.id), 0.12))

      Column() {
        Text(this.titleOf(cfg.id))
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(1)
        Text(this.subtitleOf(cfg.id))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .maxLines(1)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.removeButton(() => {
        this.onRemoveCard(cfg.id);
      })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor(Tokens.CARD_STRONG)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_INPUT)
    .margin({ bottom: 8 })
    .animation({ duration: Motion.NORMAL, curve: Motion.spring() })
    .transition(Motion.listItem())
  }

  @Builder
  addChip(def: HomeCardDef) {
    Row({ space: 5 }) {
      SymbolGlyph(def.symbol)
        .fontSize(15)
        .fontColor([def.accent])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      Text(def.title)
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)
        .maxLines(1)
      SymbolGlyph(AppSymbols.PLUS)
        .fontSize(12)
        .fontColor([def.accent])
    }
    .width('32%')
    .height(40)
    .padding({ left: 8, right: 8 })
    .margin({ bottom: 8 })
    .backgroundColor(Tokens.tint(def.accent, 0.08))
    .border({ width: 0.5, color: Tokens.tint(def.accent, 0.18) })
    .borderRadius(Tokens.RADIUS_INPUT)
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => {
      this.onAddCard(def.id);
    })
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('添加卡片')
            .fontSize(Tokens.F_HEADING)
            .fontWeight(FontWeight.Bold)
            .fontColor(Tokens.TEXT_PRIMARY)
          Text('长按卡片拖动排序 · 拖动右下角边框线缩放')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 4 }) {
          SymbolGlyph(AppSymbols.RESET)
            .fontSize(14)
            .fontColor([Tokens.SLATE_BLUE])
          Text('默认')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.SLATE_BLUE)
        }
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .borderRadius(Tokens.RADIUS_PILL)
        .backgroundColor(Tokens.tint(Tokens.SLATE_BLUE, 0.10))
        .onClick(() => {
          this.onReset();
        })
      }
      .width('100%')
      .padding({ bottom: 12 })

      Scroll() {
        Column() {
          Text('已添加 ' + this.cards.length + ' 张')
            .fontSize(Tokens.F_LABEL)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 8 })

          ForEach(this.cards, (cfg: HomeCardConfig) => {
            this.cardRow(cfg)
          }, (cfg: HomeCardConfig) => cfg.id)

          if (this.cards.length === 0) {
            Text('还没有卡片，从下方添加')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .padding({ top: 12, bottom: 12 })
          }

          Row()
            .width('100%')
            .height(0.5)
            .backgroundColor(Tokens.DIVIDER)
            .margin({ top: 8, bottom: 14 })

          Text('可添加')
            .fontSize(Tokens.F_LABEL)
            .fontColor(Tokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ bottom: 10 })

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(HomeCards.unusedDefs(this.cards), (def: HomeCardDef) => {
              this.addChip(def)
            }, (def: HomeCardDef) => def.id)
          }
          .width('100%')

          Blank().height(24)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Button('完成')
        .width('100%')
        .height(44)
        .fontSize(Tokens.F_BODY)
        .fontColor('#FFFFFF')
        .backgroundColor(Tokens.MIST_TEAL)
        .borderRadius(Tokens.RADIUS_PILL)
        .margin({ top: 8, bottom: 12 })
        .onClick(() => {
          this.onDone();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: Tokens.SPACE_16, right: Tokens.SPACE_16, top: Tokens.SPACE_8 })
    .alignItems(HorizontalAlign.Start)
  }
}
