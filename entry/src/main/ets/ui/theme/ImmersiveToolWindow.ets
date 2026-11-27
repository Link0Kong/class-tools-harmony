import { window } from '@kit.ArkUI';
import { AppGlobal } from '../../app/AppGlobal';

/** Keeps system bars in sync as dark tool pages hand off to one another. */
export class ImmersiveToolWindow {
  private static owners: Set<ImmersiveToolWindow> = new Set<ImmersiveToolWindow>();
  private static previous?: window.SystemBarProperties;

  setDark(dark: boolean): void {
    const owners = ImmersiveToolWindow.owners;
    if (!dark) {
      if (!owners.delete(this) || owners.size > 0) return;
      const previous = ImmersiveToolWindow.previous;
      ImmersiveToolWindow.previous = undefined;
      if (!previous) return;
      try {
        AppGlobal.context?.windowStage.getMainWindowSync().setWindowSystemBarProperties(previous).catch(() => {});
      } catch (_) { /* The window may already be closed. */ }
      return;
    }
    if (owners.has(this)) return;
    try {
      const mainWindow = AppGlobal.context?.windowStage.getMainWindowSync();
      if (!mainWindow) return;
      if (owners.size === 0) {
        ImmersiveToolWindow.previous = mainWindow.getWindowSystemBarProperties();
        mainWindow.setWindowSystemBarProperties({ statusBarColor: '#1B2629', statusBarContentColor: '#EFF5F1',
          navigationBarContentColor: '#EFF5F1' }).catch(() => {});
      }
      owners.add(this);
    } catch (_) { /* Keep the current bars if the window is unavailable. */ }
  }
}
