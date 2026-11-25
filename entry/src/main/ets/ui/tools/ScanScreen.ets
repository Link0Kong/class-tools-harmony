import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import { ScanPayload } from '../../data/scan/ScanPayload';
import { ScanActions } from '../../data/scan/ScanActions';
import { TaskRepository } from '../../data/tasks/TaskRepository';
import { PageHeader } from '../components/PageHeader';
import { Tokens } from '../theme/Tokens';

@Component
export struct ScanScreen {
  onClose: () => void = () => {};
  @State private link: string = '';
  @State private code: ScanPayload = new ScanPayload();
  @State private status: string = '';
  @State private busy: boolean = false;
  private owner: string = '';
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; this.owner = Services.currentSid; }
  aboutToDisappear(): void { this.active = false; this.clear(); }
  private current(): boolean { return this.active && !!this.owner && this.owner === Services.currentSid; }
  private clear(): void { this.code = new ScanPayload(); this.link = ''; this.status = ''; }

  private async recognize(raw: string): Promise<void> {
    if (!this.current()) return;
    this.clear();
    this.code = ScanPayload.parse(raw);
    if (!this.code.kind) { this.status = '未识别到枫丹工具箱的登录、抽签存证或任务链接'; return; }
    if (this.code.kind === 'draw') {
      this.busy = true;
      this.status = '正在读取存证并复算…';
      try {
        const result = await ScanActions.verify(this.code.recordId);
        if (this.current()) this.status = result.text;
      } finally { this.busy = false; }
    }
  }

  private async scan(): Promise<void> {
    const context = AppGlobal.context;
    if (!context || this.busy) return;
    this.clear();
    this.busy = true;
    try {
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE], enableAlbum: true, enableMultiMode: false });
      await this.recognize(result.originalValue);
    } catch (error) {
      if (this.current() && (error as BusinessError).code !== 1000500002) this.status = '系统扫码暂不可用，可粘贴链接识别';
    } finally { this.busy = false; }
  }

  private async authorize(allow: boolean): Promise<void> {
    if (this.busy || !this.current() || this.code.kind !== 'login') return;
    this.busy = true;
    try {
      const result = await ScanActions.login(this.code, allow);
      if (this.current()) {
        this.status = result.text;
        if (result.ok) this.code = new ScanPayload();
      }
    } finally { this.busy = false; }
  }

  private async saveTask(): Promise<void> {
    const shared = this.code.task;
    if (!shared || !this.current() || this.busy) return;
    this.busy = true;
    try {
      const saved = await TaskRepository.add(shared.title, shared);
      if (this.current()) {
        if (saved) this.clear();
        this.status = saved ? '已保存为我的任务' : '未能保存任务，请检查本机存储或任务数量';
      }
    } finally { this.busy = false; }
  }

  build() {
    PageHeader({ taskColors: true, title: '扫一扫', onBack: this.onClose }) {
      Scroll() {
        Column({ space: 14 }) {
          if (this.code.kind === 'login') {
            Text('确认网页登录').fontWeight(FontWeight.Bold).fontSize(21).fontColor($r('app.color.task_text'))
            Text('确认后，显示这张二维码的设备将以「' + Services.currentName + '」登录枫丹工具箱。')
              .fontSize(16).fontColor($r('app.color.task_text'))
            Button('这是我的设备，确认登录').enabled(!this.busy).onClick(() => { this.authorize(true); })
            Button('取消本次登录').enabled(!this.busy).onClick(() => { this.authorize(false); })
          } else if (this.code.kind === 'task' && this.code.task) {
            Text('分享的任务').fontWeight(FontWeight.Bold).fontSize(20).fontColor($r('app.color.task_text'))
            Text(this.code.task.title).fontSize(18).fontColor($r('app.color.task_text'))
            Text([this.code.task.group, this.code.task.due].filter((s: string) => !!s).join(' · ')).fontColor($r('app.color.task_muted'))
            if (this.code.task.notes) { Text(this.code.task.notes).fontColor($r('app.color.task_text')) }
            ForEach(this.code.task.steps, (s: string) => { Text('• ' + s).fontColor($r('app.color.task_text')) },
              (s: string, i: number) => i + s)
            Button('保存为我的任务').enabled(!this.busy).onClick(() => { this.saveTask(); })
          } else if (this.code.kind === 'draw') {
            Text('抽签存证核验').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.task_text'))
            Text(this.code.recordId).fontColor($r('app.color.task_muted'))
          }
          if (this.status) { Text(this.status).fontSize(16).fontColor($r('app.color.task_text')) }
          if (this.code.kind !== 'login') {
            Button('打开系统扫码').enabled(!this.busy).onClick(() => { this.scan(); })
            TextInput({ text: this.link, placeholder: '粘贴登录、抽签存证或任务链接' }).maxLength(8192)
              .onChange((s: string) => { this.link = s; })
            Button('识别链接').enabled(!this.busy && !!this.link.trim()).onClick(() => { this.recognize(this.link); })
          }
        }.width('100%').padding(18).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').align(Alignment.Top)
    }
  }
}
