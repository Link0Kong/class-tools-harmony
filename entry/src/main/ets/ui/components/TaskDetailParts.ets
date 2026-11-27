import { showFeedback } from './AppFeedback';
import { AppGlobal } from '../../app/AppGlobal';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { HomeworkAttachmentKind, HomeworkAttachmentMeta } from '../../data/homework/HomeworkModels';
import { Tokens } from '../theme/Tokens';

@Component
export struct DetailField {
  @Prop label: string = '';
  @Prop value: string = '';
  build() {
    Row({ space: 10 }) {
      Text(this.label).fontSize(14).fontColor($r('app.color.task_muted')).width(76)
      Text(this.value).fontSize(16).lineHeight(23).fontColor($r('app.color.task_text')).layoutWeight(1)
        .copyOption(CopyOptions.InApp)
    }.alignItems(VerticalAlign.Top).width('100%')
  }
}

@Component
export struct DetailSection {
  @Prop title: string = '';
  @Prop surface: ResourceColor = $r('app.color.task_card');
  @BuilderParam content: () => void = this.empty;
  @Builder empty() {}
  build() {
    Column({ space: 12 }) {
      Text(this.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.task_text'))
      this.content()
    }.alignItems(HorizontalAlign.Start).width('100%').padding(Tokens.SPACE_16)
      .backgroundColor(this.surface).borderRadius(Tokens.RADIUS_CARD)
  }
}

@Component
export struct TaskAttachmentRow {
  @Prop meta: HomeworkAttachmentMeta = new HomeworkAttachmentMeta();
  data: () => string = () => '';
  onImage: (src: string) => void = () => {};
  @State private saving: boolean = false;

  private async open(): Promise<void> {
    const ctx = AppGlobal.context;
    if (!ctx || this.saving) return;
    const src = this.data();
    const toast = (message: string): void => { showFeedback(this.getUIContext(), message); };
    if (this.meta.isImage() && src) {
      this.onImage(src);
    } else if (/^https?:\/\//i.test(src)) {
      try { await ctx.startAbility({ action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: src }); }
      catch (_) { toast('当前设备无法打开此附件'); }
    } else if (this.meta.kind === HomeworkAttachmentKind.DATA_URI) {
      const comma = src.indexOf(',');
      if (comma < 0 || !src.slice(0, comma).toLowerCase().endsWith(';base64')) { toast('附件数据格式不完整'); return; }
      this.saving = true;
      try {
        const bytes = new util.Base64Helper().decodeSync(src.slice(comma + 1));
        const options = new picker.DocumentSaveOptions();
        options.newFileNames = [this.meta.name.replace(/[\\/:*?"<>|]/g, '_')];
        const uris = await new picker.DocumentViewPicker(ctx).save(options);
        if (!uris.length) return;
        const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try { await fs.write(file.fd, bytes.buffer); } finally { fs.closeSync(file); }
        toast('附件已保存');
      } catch (_) { toast('未保存附件'); }
      finally { this.saving = false; }
    }
  }

  build() {
    Row({ space: 10 }) {
      Column({ space: 4 }) {
        Text(this.meta.name).fontSize(16).fontColor($r('app.color.task_text'))
        if (this.meta.sizeBytes > 0) {
          Text(this.meta.sizeText()).fontSize(13).fontColor($r('app.color.task_muted'))
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text(this.meta.kind === HomeworkAttachmentKind.NONE ? '仅有文件信息' :
        this.meta.isImage() ? '查看图片' : this.meta.kind === HomeworkAttachmentKind.URL ? '打开' : this.saving ? '保存中' : '保存')
        .fontSize(14).fontColor($r('app.color.task_accent'))
    }.width('100%').constraintSize({ minHeight: 44 }).onClick(() => { this.open(); })
  }
}
