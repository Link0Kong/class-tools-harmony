import { showFeedback } from '../components/AppFeedback';
import { Services } from '../../app/Services';
import { UserdataRepository } from '../../data/sync/UserdataRepository';
import { Blob, JsonBlob } from '../../data/sync/JsonBlob';
import {
  FIT_INPUT_FIELDS,
  FitCalc,
  FitFieldSpec,
  FitGrade,
  fitGradeLabel,
  FitHistory,
  FitInput,
  FitRecord,
  FitRow,
  FitSex,
  fitSexLabel,
  SavedHistory
} from '../../features/fit/FitModels';
import { FitScoring } from '../../features/fit/FitScoring';
import { FitCodec } from '../../features/fit/FitCodec';
import { ExportCardSpec, ExportNaming, FitExportFactory } from '../../features/export/ExportCard';
import { FitRecsResult, FitRecsWriteResult } from '../../data/fitrecs/FitRecsRepository';
import { Tokens } from '../theme/Tokens';
import { Immersive } from '../theme/Immersive';
import { PageHeader } from '../components/PageHeader';
import { ExportPreview } from './ExportPreview';

/**
 * 体测工具：性别/年级 + 9 项成绩 → 实时国标评分 → 保存历史（fitrecs，最多 2 条）→ 导出。
 *
 * 参数写回 `userdata.fit`（11 键，保留未知字段）；history 走 `fitrecs` + arch 软删。
 */
@Component
export struct FitScreen {
  onClose: () => void = () => {
  };

  @State private input: FitInput = new FitInput();
  @State private calc: FitCalc = new FitCalc();
  @State private records: FitRecord[] = [];
  @State private historyMsg: string = '';
  @State private renameId: string = '';
  @State private renameText: string = '';
  @State private errorMsg: string = '';
  @State private showExport: boolean = false;
  private scroller: Scroller = new Scroller();
  @State private exportSpec: ExportCardSpec = new ExportCardSpec();

  private persistTimer: number = -1;
  private userdata: UserdataRepository = Services.userdata;

  aboutToAppear(): void {
    this.restore();
    this.loadHistory();
  }

  aboutToDisappear(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer);
      this.persistTimer = -1;
    }
    this.persist();
  }

  private restore(): void {
    const sections: Blob = this.userdata.currentSections();
    this.input = FitCodec.inputFromJson(JsonBlob.get(sections, 'fit'));
    this.calc = FitScoring.calc(this.input);
  }

  private async loadHistory(): Promise<void> {
    const result: FitRecsResult = await Services.fitRecs.refresh(false);
    this.records = result.records;
    if (!result.ok) {
      this.historyMsg = result.message;
    }
  }

  private fieldSpec(key: string): FitFieldSpec {
    for (let i = 0; i < FIT_INPUT_FIELDS.length; i++) {
      if (FIT_INPUT_FIELDS[i].key === key) {
        return FIT_INPUT_FIELDS[i];
      }
    }
    return new FitFieldSpec(key, key, '', 0);
  }

  private onFieldChange(key: string, text: string): void {
    const clean: string = FitScoring.sanitizeInput(text, this.fieldSpec(key));
    this.input = this.input.withValue(key, clean);
    this.calc = FitScoring.calc(this.input);
    this.errorMsg = '';
    this.schedulePersist();
  }

  private onDurationChange(minutes: boolean, text: string): void {
    const clean: string = FitScoring.sanitizeInput(text, new FitFieldSpec('dur', '长跑', '', 0));
    this.input = this.input.withValue(minutes ? 'durM' : 'durS', clean);
    this.calc = FitScoring.calc(this.input);
    this.errorMsg = '';
    this.schedulePersist();
  }

  private schedulePersist(): void {
    if (this.persistTimer >= 0) {
      clearTimeout(this.persistTimer);
    }
    this.persistTimer = setTimeout(() => {
      this.persistTimer = -1;
      this.persist();
    }, 700);
  }

  private async persist(): Promise<void> {
    const current: Blob = this.userdata.currentSections();
    const next: Blob = {};
    const keys: string[] = JsonBlob.keys(current);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = current[keys[i]];
    }
    const existing: Blob | undefined = JsonBlob.asBlob(JsonBlob.get(current, 'fit'));
    next['fit'] = FitCodec.toJson(this.input, existing);
    await this.userdata.updateCurrent(next);
  }

  private scoreOfKey(key: string): number | undefined {
    // 评分行顺序：0 体重指数 / 1 肺活量 / 2 50米 / 3 坐位体前屈 / 4 立定跳远 / 5 引体(仰卧) / 6 长跑
    let index: number = -1;
    if (key === 'h' || key === 'w') {
      index = 0;
    } else if (key === 'vc') {
      index = 1;
    } else if (key === 'r50') {
      index = 2;
    } else if (key === 'sit') {
      index = 3;
    } else if (key === 'jump') {
      index = 4;
    } else if (key === 'pull') {
      index = 5;
    } else if (key === 'dur') {
      index = 6;
    }
    if (index < 0 || index >= this.calc.rows.length) {
      return undefined;
    }
    return this.calc.rows[index].score;
  }

  /** 清空成绩（保留性别/年级）。 */
  private clearForm(): void {
    const next: FitInput = new FitInput();
    next.sex = this.input.sex;
    next.grade = this.input.grade;
    this.input = next;
    this.calc = FitScoring.calc(next);
    this.errorMsg = '';
    this.persist();
  }

  private async saveRecord(): Promise<void> {
    if (!this.input.hasAny()) {
      this.errorMsg = '请先填写至少一项成绩';
      return;
    }
    const now: number = Date.now();
    const id: string = 'fit_' + now + '_' + Math.floor(Math.random() * 10000);
    const saved: SavedHistory = FitHistory.save(this.records, this.input, this.calc, id, now, '');
    if (saved.record === undefined) {
      this.errorMsg = '保存失败';
      return;
    }
    const write: FitRecsWriteResult = await Services.fitRecs.save(saved.record);
    for (let i = 0; i < saved.dropped.length; i++) {
      await Services.fitRecs.archive(saved.dropped[i].id);
    }
    this.records = saved.records;
    this.errorMsg = '';
    showFeedback(this.getUIContext(), write.ok ? '已保存到历史（云端）' : '已保存到本机（云端同步失败，稍后重试）');
  }

  private async deleteRecord(index: number): Promise<void> {
    if (index < 0 || index >= this.records.length) {
      return;
    }
    const id: string = this.records[index].id;
    this.records = FitHistory.deleteAt(this.records, index);
    await Services.fitRecs.archive(id);
    showFeedback(this.getUIContext(), '已删除');
  }

  private async saveRename(): Promise<void> {
    if (this.renameId.length === 0) {
      return;
    }
    const target = this.records.find((item: FitRecord) => item.id === this.renameId);
    if (target === undefined) {
      this.renameId = '';
      return;
    }
    const result = await Services.fitRecs.rename(target, this.renameText);
    if (!result.ok) {
      showFeedback(this.getUIContext(), '改名失败，请稍后重试');
      return;
    }
    const next: FitRecord[] = [];
    for (let i = 0; i < this.records.length; i++) {
      const item: FitRecord = this.records[i];
      if (item.id === this.renameId) {
        const trimmed: string = this.renameText.trim();
        const copy: FitRecord = new FitRecord();
        copy.id = item.id;
        copy.ts = item.ts;
        copy.name = trimmed;
        copy.sex = item.sex;
        copy.gradeBucket = item.gradeBucket;
        copy.fields = item.fields;
        copy.total = item.total;
        copy.grade = item.grade;
        copy.syncPending = item.syncPending;
        next.push(copy);
      } else {
        next.push(item);
      }
    }
    this.records = next;
    this.renameId = '';
    showFeedback(this.getUIContext(), '已改名');
  }

  private restoreRecord(index: number): void {
    const restored: FitInput | undefined = FitHistory.restoreAt(this.records, index);
    if (restored === undefined) {
      return;
    }
    this.input = restored;
    this.calc = FitScoring.calc(restored);
    showFeedback(this.getUIContext(), '已回填该记录');
    this.persist();
  }

  private openExport(): void {
    if (!this.input.hasAny()) {
      this.errorMsg = '请先填写成绩再导出';
      return;
    }
    this.exportSpec = FitExportFactory.create(this.calc, this.input, Date.now(), ExportNaming.randomSuffix());
    this.showExport = true;
  }

  @Builder
  sexChip(value: FitSex) {
    Text(fitSexLabel(value))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.input.sex === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.input.sex === value ? Tokens.MIST_TEAL : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        const next: FitInput = this.input.copy();
        next.sex = value;
        this.input = next;
        this.calc = FitScoring.calc(this.input);
        this.persist();
      })
  }

  @Builder
  gradeChip(value: FitGrade) {
    Text(fitGradeLabel(value))
      .fontSize(Tokens.F_CAPTION)
      .fontColor(this.input.grade === value ? '#FFFFFF' : Tokens.TEXT_SECONDARY)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.input.grade === value ? Tokens.SLATE_BLUE : Tokens.CONTROL)
      .borderRadius(Tokens.RADIUS_PILL)
      .margin({ right: 8 })
      .onClick(() => {
        const next: FitInput = this.input.copy();
        next.grade = value;
        this.input = next;
        this.calc = FitScoring.calc(this.input);
        this.persist();
      })
  }

  @Builder
  fieldRow(spec: FitFieldSpec) {
    Row() {
      Text(spec.label)
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width(120)
      TextInput({ text: this.input.valueOf(spec.key), placeholder: spec.unit })
        .type(InputType.NUMBER_DECIMAL)
        .height(40)
        .layoutWeight(1)
        .backgroundColor(Tokens.CONTROL)
        .borderRadius(8)
        .fontSize(Tokens.F_BODY)
        .onChange((text: string) => {
          this.onFieldChange(spec.key, text);
        })
      Text(this.scoreOfKey(spec.key) !== undefined ? this.scoreOfKey(spec.key) + ' 分' : '—')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width(56)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
  }

  @Builder
  durationRow() {
    Row() {
      Text('长跑（分·秒）')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.TEXT_SECONDARY)
        .width(120)
      TextInput({ text: this.input.durM, placeholder: '分' })
        .type(InputType.Number)
        .height(40)
        .width(64)
        .backgroundColor(Tokens.CONTROL)
        .borderRadius(8)
        .fontSize(Tokens.F_BODY)
        .onChange((text: string) => {
          this.onDurationChange(true, text);
        })
      Text('′')
        .fontSize(Tokens.F_BODY)
        .fontColor(Tokens.TEXT_TERTIARY)
        .margin({ left: 4, right: 4 })
      TextInput({ text: this.input.durS, placeholder: '秒' })
        .type(InputType.Number)
        .height(40)
        .width(64)
        .backgroundColor(Tokens.CONTROL)
        .borderRadius(8)
        .fontSize(Tokens.F_BODY)
        .onChange((text: string) => {
          this.onDurationChange(false, text);
        })
      Blank()
      Text(this.scoreOfKey('dur') !== undefined ? this.scoreOfKey('dur') + ' 分' : '—')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width(56)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .height(48)
  }

  @Builder
  summaryCard() {
    Column() {
      Row() {
        Text(this.calc.totalText)
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text(this.calc.grade)
          .fontSize(Tokens.F_LABEL)
          .fontColor(this.calc.grade === '不及格' ? Tokens.DANGER : Tokens.MIST_TEAL)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(this.calc.grade === '不及格' ? Tokens.TINT_SAND : Tokens.TINT_TEAL)
          .borderRadius(Tokens.RADIUS_PILL)
          .margin({ left: 10 })
        Blank()
      }
      .width('100%')

      Text('标准分 ' + this.calc.std.toFixed(1) + ' · 附加分 ' + this.calc.plus.toFixed(1)
        + ' · 已测权重 ' + this.calc.wtDone + ' / 100'
        + (this.calc.miss > 0 ? ' · 缺 ' + this.calc.miss + ' 项' : ''))
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 4, bottom: 8 })

      ForEach(this.calc.rows, (row: FitRow) => {
        Row() {
          Text(row.name + ' · ' + row.value + ' ' + row.sub)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_SECONDARY)
            .layoutWeight(1)
          Text(row.weight + '%')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width(44)
            .textAlign(TextAlign.End)
          Text(row.score !== undefined ? row.score + ' 分' : '缺项')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(row.score !== undefined ? Tokens.TEXT_PRIMARY : Tokens.TEXT_TERTIARY)
            .width(56)
            .textAlign(TextAlign.End)
          if (row.plus > 0) {
            Text('+' + row.plus)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.WARM_SAND)
              .width(34)
              .textAlign(TextAlign.End)
          }
        }
        .width('100%')
        .height(26)
      }, (row: FitRow, index: number) => row.name + '_' + row.value + '_' + (row.score !== undefined ? row.score : 'x'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
  }

  @Builder
  historyCard() {
    Column() {
      Row() {
        Text('历史记录')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        if (this.historyMsg.length > 0) {
          Text(this.historyMsg)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.MIST_TEAL)
        }
      }
      .width('100%')

      if (this.renameId.length > 0) {
        Row({ space: 8 }) {
          TextInput({ text: this.renameText, placeholder: '记录名称' })
            .layoutWeight(1)
            .height(38)
            .backgroundColor(Tokens.CONTROL)
            .fontSize(Tokens.F_CAPTION)
            .borderRadius(8)
            .onChange((value: string) => {
              this.renameText = value;
            })
          Button('保存')
            .height(34)
            .fontSize(Tokens.F_CAPTION)
            .backgroundColor(Tokens.MIST_TEAL)
            .fontColor('#FFFFFF')
            .borderRadius(Tokens.RADIUS_PILL)
            .onClick(() => {
              this.saveRename();
            })
          Button('取消')
            .height(34)
            .fontSize(Tokens.F_CAPTION)
            .backgroundColor(Tokens.CONTROL)
            .fontColor(Tokens.TEXT_SECONDARY)
            .borderRadius(Tokens.RADIUS_PILL)
            .onClick(() => {
              this.renameId = '';
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
      if (this.records.length === 0) {
        Text('暂无历史（保存后最多保留 2 条）')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 8 })
      } else {
        ForEach(this.records, (record: FitRecord, index: number) => {
          Column() {
            Row() {
              Text(record.displayName())
                .fontSize(Tokens.F_LABEL)
                .fontColor(Tokens.TEXT_PRIMARY)
                .layoutWeight(1)
              Text(record.totalText() + ' · ' + record.grade)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
            }
            .width('100%')
            Text(record.detailText())
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .maxLines(2)
              .margin({ top: 2 })
            Row() {
              Text('改名')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.SLATE_BLUE)
                .padding({ right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.renameId = record.id;
                  this.renameText = record.displayName();
                })
              Text('回填')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
                .padding({ right: 14, top: 6, bottom: 6 })
                .onClick(() => {
                  this.restoreRecord(index);
                })
              Text('删除')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.DANGER)
                .backgroundColor(Tokens.CONTROL)
                .border({ width: 0.5, color: Tokens.CARD_EDGE })
                .borderRadius(Tokens.RADIUS_PILL)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ left: 8 })
                .onClick(() => {
                  this.deleteRecord(index);
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
        }, (record: FitRecord, index: number) => record.id + '_' + index + '_' + record.name)
      }
    }
    .width('100%')
    .padding(16)
    .margin({ top: 14 })
    .backgroundColor(Tokens.CARD)
    .border({ width: 0.5, color: Tokens.CARD_EDGE })
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  @State private headerFade: number = 0;

  build() {
    Stack() {
      PageHeader({
      progress: this.headerFade,
        title: '体测',
        scroller: this.scroller,
        onBack: () => {
          this.onClose();
        }
      }) {
        Column() {
          Scroll(this.scroller) {
          Column() {
            Row() {
              this.sexChip(FitSex.MALE)
              this.sexChip(FitSex.FEMALE)
              Blank()
            }
            .width('100%')
            .margin({ bottom: 8 })

            Row() {
              this.gradeChip(FitGrade.G12)
              this.gradeChip(FitGrade.G34)
              Blank()
            }
            .width('100%')
            .margin({ bottom: 6 })

            Column() {
              this.fieldRow(FIT_INPUT_FIELDS[0])
              this.fieldRow(FIT_INPUT_FIELDS[1])
              this.fieldRow(FIT_INPUT_FIELDS[2])
              this.fieldRow(FIT_INPUT_FIELDS[3])
              this.fieldRow(FIT_INPUT_FIELDS[4])
              this.fieldRow(FIT_INPUT_FIELDS[5])
              this.fieldRow(FIT_INPUT_FIELDS[6])
              this.durationRow()
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor(Tokens.CARD)
            .border({ width: 0.5, color: Tokens.CARD_EDGE })
            .borderRadius(Tokens.RADIUS_CARD)

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.DANGER)
                .width('100%')
                .margin({ top: 10 })
            }

            Column() {
              this.summaryCard()
            }
            .margin({ top: 14 })

            Row({ space: 10 }) {
              Button('保存到历史')
                .layoutWeight(2)
                .height(46)
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.saveRecord();
                })
              Button('更多')
                .layoutWeight(1)
                .height(46)
                .backgroundColor(Tokens.CONTROL)
                .border({ width: 0.5, color: Tokens.CARD_EDGE })
                .fontColor(Tokens.TEXT_SECONDARY)
                .borderRadius(Tokens.RADIUS_PILL)
                .bindMenu([
                  {
                    value: '清空本次输入',
                    action: () => {
                      this.clearForm();
                    }
                  },
                  {
                    value: '导出图片',
                    action: () => {
                      this.openExport();
                    }
                  }
                ], { systemMaterial: Immersive.dialogMaterial() })
            }
            .width('100%')
            .margin({ top: 14 })

            this.historyCard()
          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .onDidScroll((offset: number) => {
          const next: number = offset <= 0 ? 0 : (offset >= 56 ? 1 : offset / 56);
          if (Math.abs(next - this.headerFade) > 0.03) {
            this.headerFade = next;
          }
        })
        }
        .width('100%')
        .height('100%')
        .padding({ top: 0 })
      }

      if (this.showExport) {
        ExportPreview({
          spec: this.exportSpec,
          onClose: () => {
            this.showExport = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}

