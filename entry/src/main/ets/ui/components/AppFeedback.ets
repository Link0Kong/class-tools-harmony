import { promptAction, UIContext } from '@kit.ArkUI';

/** 让临时操作反馈显示在当前应用的前景，避开底栏、底部面板和输入法。 */
export function showFeedback(context: UIContext, message: string): void {
  const text: string = message.trim();
  if (text.length === 0) return;
  try {
    context.getPromptAction().showToast({
      message: text,
      duration: text.length > 60 ? 10000 : 4000,
      showMode: promptAction.ToastShowMode.TOP_MOST,
      alignment: Alignment.Top,
      offset: { dx: 0, dy: context.vp2px(8) },
      backgroundColor: $r('app.color.feedback_surface'),
      textColor: $r('app.color.feedback_text'),
      backgroundBlurStyle: BlurStyle.NONE,
      shadow: ShadowStyle.OUTER_DEFAULT_SM,
      enableHoverMode: true,
      hoverModeArea: HoverModeAreaType.TOP_SCREEN
    });
  } catch (_) {
    // 组件退出时 UIContext 可能已失效，保留原操作结果。
  }
}

/** 站内 WebView 的提示留在页面的前景层，并和原生提示使用相同配色。 */
export const EMBEDDED_FEEDBACK_SCRIPT: string = `
  (() => {
    if (document.getElementById('ct-feedback-style')) return;
    const style = document.createElement('style');
    style.id = 'ct-feedback-style';
    style.textContent = \`
      html body #toast {
        position: fixed; inset: 8px auto auto 50%; z-index: 2147483647;
        box-sizing: border-box; width: max-content; max-width: min(480px, calc(100% - 32px));
        background: #1C2629; color: #F4F6F6; border: 0; border-radius: 16px;
        padding: 12px 16px; font-size: .875rem; line-height: 1.4; text-align: start;
        overflow-wrap: anywhere; pointer-events: none; transform: translateX(-50%);
      }
      html[data-appearance=dark] body #toast, html[data-theme=dark] body #toast {
        background: #ECF1F6; color: #18212C;
      }
    \`;
    document.head.append(style);
  })();`;
