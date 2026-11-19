import { describe, it, expect } from '@ohos/hypium';
import { Breakpoints } from '../main/ets/ui/theme/Breakpoints';
import { Tokens } from '../main/ets/ui/theme/Tokens';
import { ToolCatalog, ToolDef } from '../main/ets/data/tool/ToolCatalog';

export default function breakpointsTest() {
  describe('Breakpoints', () => {
    it('grid_columns_2_3_4', 0, () => {
      expect(Breakpoints.gridColumns(0)).assertEqual(2);
      expect(Breakpoints.gridColumns(360)).assertEqual(2);
      expect(Breakpoints.gridColumns(599)).assertEqual(2);
      expect(Breakpoints.gridColumns(600)).assertEqual(3);
      expect(Breakpoints.gridColumns(899)).assertEqual(3);
      expect(Breakpoints.gridColumns(900)).assertEqual(4);
      expect(Breakpoints.gridColumns(1200)).assertEqual(4);
    });

    it('grid_item_width_percent', 0, () => {
      expect(Breakpoints.gridItemWidthPercent(360)).assertEqual('48.5%');
      expect(Breakpoints.gridItemWidthPercent(700)).assertEqual('31.5%');
      expect(Breakpoints.gridItemWidthPercent(1000)).assertEqual('23.5%');
    });

    it('content_max_width_and_breath', 0, () => {
      expect(Breakpoints.contentMaxWidth(360)).assertEqual(880);
      expect(Breakpoints.contentMaxWidth(700)).assertEqual(880);
      expect(Breakpoints.contentMaxWidth(1200)).assertEqual(1080);
      expect(Breakpoints.breathTop(360)).assertEqual(8);
      expect(Breakpoints.breathTop(1200)).assertEqual(12);
      expect(Breakpoints.contentBottomSpace(360)).assertEqual(96);
      expect(Breakpoints.contentBottomSpace(1200)).assertEqual(32);
      expect(Breakpoints.toolContentMaxWidth(360) > 10000).assertTrue();
      expect(Breakpoints.toolContentMaxWidth(1200)).assertEqual(960);
      expect(Breakpoints.useSideNav(899)).assertFalse();
      expect(Breakpoints.useSideNav(900)).assertTrue();
      expect(Tokens.BREATH_TOP).assertEqual(8);
    });

    it('wide_and_tablet_flags', 0, () => {
      expect(Breakpoints.isWide(899)).assertFalse();
      expect(Breakpoints.isWide(900)).assertTrue();
      expect(Breakpoints.isTablet(599)).assertFalse();
      expect(Breakpoints.isTablet(600)).assertTrue();
      expect(Breakpoints.isTablet(900)).assertFalse();
      expect(Breakpoints.useTwoPane(700)).assertFalse();
      expect(Breakpoints.useTwoPane(1000)).assertTrue();
    });
  });

  describe('VisualTokens', () => {
    it('hero_is_neutral_dark_not_brand_green', 0, () => {
      // 深色 hero 是中性色：RGB 三通道接近（低饱和），且不是品牌绿 #4E9082。
      const hex: string = Tokens.HERO_DARK;
      expect(hex.startsWith('#') && hex.length === 7).assertTrue();
      const r: number = parseInt(hex.substring(1, 3), 16);
      const g: number = parseInt(hex.substring(3, 5), 16);
      const b: number = parseInt(hex.substring(5, 7), 16);
      expect(Math.abs(r - g) <= 20).assertTrue();
      expect(Math.abs(g - b) <= 20).assertTrue();
      expect((r + g + b) / 3 < 90).assertTrue();
      expect(hex.toUpperCase() === Tokens.MIST_TEAL.toUpperCase()).assertFalse();
      // 正文/副标与 hero 底色对比：浅色文字。
      expect(Tokens.HERO_TEXT.toUpperCase() === '#F3F6F6').assertTrue();
    });

    it('bottom_bar_is_light_no_dark_shadow', 0, () => {
      const bar: string = Tokens.BAR_LIGHT;
      const r: number = parseInt(bar.substring(1, 3), 16);
      const g: number = parseInt(bar.substring(3, 5), 16);
      const b: number = parseInt(bar.substring(5, 7), 16);
      expect((r + g + b) / 3 > 240).assertTrue();
      // 底栏用发丝线而不是黑影：分隔线是浅灰。
      const divider: string = Tokens.DIVIDER;
      const dr: number = parseInt(divider.substring(1, 3), 16);
      expect(dr > 200).assertTrue();
    });

    it('tool_description_two_lines_capacity', 0, () => {
      // 卡片副标最多两行：所有工具副标都非空，且 96vp 卡高可容纳 2 行（12vp * 17 行高）。
      expect(ToolCatalog.ALL.length >= 16).assertTrue();
      for (let i = 0; i < ToolCatalog.ALL.length; i++) {
        const tool: ToolDef = ToolCatalog.ALL[i];
        expect(tool.subtitle.length > 0).assertTrue();
        expect(tool.subtitle.length <= 40).assertTrue();
      }
    });
  });

  describe('ToolCatalogPorting', () => {
    it('new_tools_registered', 0, () => {
      const ids: string[] = [];
      for (let i = 0; i < ToolCatalog.ALL.length; i++) {
        ids.push(ToolCatalog.ALL[i].id);
      }
      expect(ids.indexOf('map') >= 0).assertTrue();
      expect(ids.indexOf('file') >= 0).assertTrue();
      expect(ids.length).assertEqual(16);
    });

    it('ids_unique_and_features_present', 0, () => {
      const seen: string[] = [];
      for (let i = 0; i < ToolCatalog.ALL.length; i++) {
        const tool: ToolDef = ToolCatalog.ALL[i];
        expect(seen.indexOf(tool.id)).assertEqual(-1);
        seen.push(tool.id);
        expect(tool.name.length > 0).assertTrue();
        expect(tool.symbol !== undefined).assertTrue();
        expect(tool.features.length > 0).assertTrue();
        expect(ToolCatalog.byId(tool.id) !== undefined).assertTrue();
      }
      expect(ToolCatalog.byId('not-exist') === undefined).assertTrue();
    });
  });
}
