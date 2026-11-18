import { describe, it, expect } from '@ohos/hypium';
import { MapConfig, MapLoadState, MapLogic } from '../main/ets/features/map/MapModels';

export default function mapTest() {
  describe('MapUrl', () => {
    it('page_url_matches_ecs_h5', 0, () => {
      expect(MapLogic.pageUrl()).assertEqual('http://121.196.47.2/map/campus_final_25d.html?embed=1');
      expect(MapLogic.pageUrl().indexOf('embed=1') > 0).assertTrue();
      expect(MapLogic.host()).assertEqual('121.196.47.2');
      expect(MapConfig.PAGE_PATH.indexOf('campus_final_25d.html') > 0).assertTrue();
    });

    it('host_of_handles_port_userinfo_scheme', 0, () => {
      expect(MapLogic.hostOf('http://121.196.47.2/map/a.html?x=1')).assertEqual('121.196.47.2');
      expect(MapLogic.hostOf('https://user:pass@121.196.47.2:8443/x')).assertEqual('121.196.47.2');
      expect(MapLogic.hostOf('121.196.47.2/map')).assertEqual('');
      expect(MapLogic.hostOf('https://')).assertEqual('');
    });

    it('allowlist_only_ecs_host', 0, () => {
      expect(MapLogic.isAllowedNavigation('http://121.196.47.2/map/a.html')).assertTrue();
      expect(MapLogic.isAllowedNavigation('https://121.196.47.2/other')).assertTrue();
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
