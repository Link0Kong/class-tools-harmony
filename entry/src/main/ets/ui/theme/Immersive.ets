import { uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 沉浸光感（Spatial UI）材质工具。
 *
 * 设计原则（参考《沉浸光感》最佳实践）：
 * - 把光感当作"稀缺"视觉资源：底部悬浮导航 / 标题栏 / 弹窗等框架级表面才使用完整材质；
 * - 内容卡片使用轻量玻璃（半透明 + 背景模糊），避免大面积 GPU 消耗；
 * - 材质等级始终交给系统自适应（getGlobalMaterialLevel / ADAPTIVE）。
 */
export class Immersive {
  /** 设备是否支持沉浸式系统材质。 */
  static supported(): boolean {
    try {
      return uiMaterial.isImmersiveMaterialSupported();
    } catch (e) {
      return false;
    }
  }

  /** 当前设备的材质档位（强 / 均衡 / 弱）。 */
  static levelLabel(): string {
    try {
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      if (level === uiMaterial.MaterialLevel.EXQUISITE) {
        return '强';
      }
      if (level === uiMaterial.MaterialLevel.GENTLE) {
        return '均衡';
      }
      return '弱';
    } catch (e) {
      return '均衡';
    }
  }

  /** HDS 材质档位：设备不支持 IMMERSIVE 时自动降级到 SMOOTH。 */
  static hdsLevel(): hdsMaterial.MaterialLevel {
    try {
      const types: hdsMaterial.MaterialType[] = hdsMaterial.getSystemMaterialTypes();
      if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
        return hdsMaterial.MaterialLevel.SMOOTH;
      }
    } catch (e) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  /** 悬浮底部导航：通透、可交互、带按压光效。 */
  static navMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      materialColor: '#1FFFFFFF',
      interactive: true,
      lightEffect: { color: undefined }
    });
  }

  /** 标题栏 / 页面顶栏：更薄，内容可透出。 */
  static titleMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: '#14FFFFFF',
      interactive: true,
      lightEffect: { color: undefined }
    });
  }

  /** 弹窗 / 菜单 / Toast：更厚，保证可读性。 */
  static dialogMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }

  /** 底部抽屉 / 半模态：最厚材质，大面积内容也保持清晰。 */
  static sheetMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }

  /** 内容区次要按钮 / 分段选择：极薄、带按压光效，替代实色底。 */
  static controlMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }
}
