import { Tokens } from '../theme/Tokens';

/** 品牌标记：三圆点几何（与网页 favicon / 小程序 / 安卓 BrandMark 一致）。 */
@Component
export struct BrandMark {
  @Prop markSize: number = 22;

  build() {
    Row({ space: this.markSize * 0.22 }) {
      Circle().width(this.markSize * 0.42).height(this.markSize * 0.42).fill(Tokens.MIST_TEAL)
      Circle().width(this.markSize * 0.42).height(this.markSize * 0.42).fill(Tokens.SLATE_BLUE)
      Circle().width(this.markSize * 0.42).height(this.markSize * 0.42).fill(Tokens.WARM_SAND)
    }
    .alignItems(VerticalAlign.Center)
  }
}
