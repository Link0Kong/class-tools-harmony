import { describe, it, expect } from '@ohos/hypium';
import { MapConfig, MapLoadState, MapLogic } from '../main/ets/features/map/MapModels';

export default function mapTest() {
  describe('MapUrl', () => {
    it('page_url_matches_formal_h5', 0, () => {
      expect(MapLogic.pageUrl()).assertEqual('https://tool.furina.fun/map/campus_final_25d.html?v=20261127-map3&embed=1&native=1');
      expect(MapLogic.pageUrl().indexOf('embed=1') > 0).assertTrue();
      expect(MapLogic.host()).assertEqual('tool.furina.fun');
      expect(MapConfig.PAGE_PATH.indexOf('campus_final_25d.html') > 0).assertTrue();
      expect(MapLogic.pageUrl(' 01104 ', false).endsWith('&room=01104')).assertTrue();
      expect(MapLogic.pageUrl('01 104', false).indexOf('embed=1')).assertEqual(-1);
      expect(MapLogic.isLocalPage('resource://RAWFILE/map/campus_final_25d.html')).assertTrue();
      expect(MapLogic.pageUrl('01104', true, true).startsWith('resource://rawfile/map/campus_final_25d.html?')).assertTrue();
    });

    it('host_of_handles_port_userinfo_scheme', 0, () => {
      expect(MapLogic.hostOf('https://tool.furina.fun/map/a.html?x=1')).assertEqual('tool.furina.fun');
      expect(MapLogic.hostOf('https://user:pass@tool.furina.fun:8443/x')).assertEqual('tool.furina.fun');
      expect(MapLogic.hostOf('tool.furina.fun/map')).assertEqual('');
      expect(MapLogic.hostOf('https://')).assertEqual('');
    });

    it('allowlist_only_formal_host', 0, () => {
      expect(MapLogic.isAllowedNavigation('https://tool.furina.fun/map/a.html')).assertTrue();
      expect(MapLogic.isAllowedNavigation('https://tool.furina.fun/other')).assertTrue();
      expect(MapLogic.isAllowedNavigation('http://evil.example.com/map')).assertFalse();
      expect(MapLogic.isAllowedNavigation('javascript:alert(1)')).assertFalse();
      expect(MapLogic.isAllowedNavigation('file:///data/x.html')).assertFalse();
    });

    it('load_state_messages', 0, () => {
      expect(MapLogic.stateText(MapLoadState.LOADING)).assertEqual('正在加载校园地图…');
      expect(MapLogic.stateText(MapLoadState.FAILED).indexOf('失败') > 0).assertTrue();
      expect(MapLogic.stateText(MapLoadState.READY)).assertEqual('');
      expect(MapLogic.showErrorBar(MapLoadState.FAILED)).assertTrue();
      expect(MapLogic.showErrorBar(MapLoadState.READY)).assertFalse();
      expect(MapLogic.canOpenInBrowser()).assertTrue();
    });
  });
}
