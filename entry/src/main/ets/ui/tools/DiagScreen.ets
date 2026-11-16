import { Services } from '../../app/Services';
import {
  DiagAnalysis,
  DiagCheck,
  DiagAnalysisResult,
  DiagHealthResult,
  DiagStatus,
  DiagSummary,
  RepairTask,
  ServiceHealthRow,
  diagStatusColor,
  diagStatusLabel
} from '../../data/diag/DiagModels';
import { DiagRepository, GatewayProbe } from '../../data/diag/DiagRepository';
import { DiagReport, DiagThrottle } from '../../data/diag/DiagReport';
import { DiagReportStore } from '../../data/diag/DiagReportStore';
import { Blob } from '../../data/sync/JsonBlob';
import { DeviceChecks } from '../../features/diag/DeviceChecks';
import { Tokens } from '../theme/Tokens';
import { PageHeader } from '../components/PageHeader';

/**
 * 诊断工具：本机设备检查 + 服务健康 + AI 分析/修复任务（只读）。
 *
 * - 设备检查全部本地计算（版本/型号/系统/存储/网关延迟/会话），不上报；
 * - 服务健康 `service_health`、分析 `diag_analysis`、修复 `repair_tasks` 均为只读；
 * - client_diag 上报（本机检查 + 服务健康，指纹 10 分钟限流）；修复仍由本机代理执行。
 */
@Component
export struct DiagScreen {
  onClose: () => void = () => {
  };

  @State private summary: DiagSummary = new DiagSummary();
  @State private health: ServiceHealthRow[] = [];
  @State private analyses: DiagAnalysis[] = [];
  @State private repairs: RepairTask[] = [];
  @State private loading: boolean = true;
  @State private errorMsg: string = '';
  @State private reportNotice: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading = this.summary.checks.length === 0;
    this.errorMsg = '';
    const probe: GatewayProbe = await Services.diag.probe();
    this.summary = await DeviceChecks.run(probe.ok, probe.latencyMs);
    const healthResult: DiagHealthResult = await Services.diag.health();
    this.health = healthResult.rows;
    if (!healthResult.ok) {
      this.errorMsg = healthResult.message;
    }
    const analysisResult: DiagAnalysisResult = await Services.diag.analyses();
    this.analyses = analysisResult.analyses;
    this.repairs = analysisResult.repairs;
    this.loading = false;
  }

  private async reportAnomalies(): Promise<void> {
    const now: number = Date.now();
    const last: number = await DiagReportStore.lastReportAt();
    if (!DiagThrottle.canReport(last, now)) {
      this.reportNotice = '10 分钟内已上报过，请稍后再试';
      return;
    }
    const row: Blob | undefined = DiagReport.buildAll(this.summary.checks, this.health, now);
    if (row === undefined) {
      this.reportNotice = '当前没有需要上报的异常';
      return;
    }
    const ok: boolean = await Services.diag.report(row);
    if (ok) {
      await DiagReportStore.markReported(now);
      this.reportNotice = '已上报，本机代理会尽快处理';
    } else {
      this.reportNotice = '上报失败，请稍后重试';
    }
  }

  private checkedText(row: ServiceHealthRow): string {
    if (row.checkedAt.length === 0) {
      return '';
    }
    const stamp: number = Date.parse(row.checkedAt);
    if (!Number.isFinite(stamp)) {
      return row.checkedAt;
    }
    const d: Date = new Date(stamp);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  private timeText(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const d: Date = new Date(ts);
    return pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
  }

  @Builder
  statusChip(status: DiagStatus, label: string) {
    Text(label)
      .fontSize(Tokens.F_CAPTION)
      .fontColor('#FFFFFF')
      .padding({ left: 8, right: 8, top: 1, bottom: 1 })
      .backgroundColor(diagStatusColor(status))
      .borderRadius(6)
  }

  @Builder
  checkRow(row: DiagAnalysis) {
    Column() {
      Row() {
        Text(row.title.length > 0 ? row.title : row.id)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
          .maxLines(2)
        Text(this.timeText(row.ts))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ left: 8 })
      }
      .width('100%')
      if (row.cause.length > 0) {
        Text(row.cause)
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_SECONDARY)
          .width('100%')
          .maxLines(2)
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      PageHeader({
        title: '诊断',
        actionText: this.loading ? '' : '重测',
        onBack: () => {
          this.onClose();
        },
        onAction: () => {
          this.refresh();
        }
      })

      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Row() {
              Text('本机检查')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
              Blank()
              if (this.summary.warnCount() + this.summary.failCount() + DiagReport.fromHealth(this.health).length > 0) {
                Text('上报异常')
                  .fontSize(Tokens.F_CAPTION)
                  .fontColor(Tokens.SLATE_BLUE)
                  .padding({ left: 8, right: 8 } )
                  .onClick(() => {
                    this.reportAnomalies();
                  })
              }
              Text('通过 ' + this.summary.passCount()
                + ' · 注意 ' + this.summary.warnCount()
                + ' · 异常 ' + this.summary.failCount())
                .fontSize(Tokens.F_CAPTION)
                .fontColor(this.summary.overall() === DiagStatus.PASS ? Tokens.MIST_TEAL : Tokens.WARM_SAND)
            }
            .width('100%')

            Column() {
              ForEach(this.summary.checks, (check: DiagCheck) => {
                Row() {
                  Text(check.label)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.TEXT_SECONDARY)
                    .width(80)
                  Text(check.value)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.TEXT_PRIMARY)
                    .layoutWeight(1)
                    .maxLines(1)
                  this.statusChip(check.status, diagStatusLabel(check.status))
                }
                .width('100%')
                .padding({ top: 7, bottom: 7 })
              }, (check: DiagCheck) => check.id)
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .margin({ top: 8 })
            .backgroundColor(Tokens.CARD)
            .borderRadius(Tokens.RADIUS_CARD)

            if (this.reportNotice.length > 0) {
              Text(this.reportNotice)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
                .width('100%')
                .margin({ top: 8 })
            }

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.WARM_SAND)
                .width('100%')
                .margin({ top: 8 })
            }

            Row() {
              Text('服务健康')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
              Blank()
              Text(this.health.length + ' 项')
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.TEXT_TERTIARY)
            }
            .width('100%')
            .margin({ top: 14 })

            Column() {
              ForEach(this.health, (row: ServiceHealthRow) => {
                Row() {
                  Column() {
                    Text(row.name.length > 0 ? row.name : row.id)
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.TEXT_PRIMARY)
                    if (row.detail.length > 0) {
                      Text(row.detail)
                        .fontSize(Tokens.F_CAPTION)
                        .fontColor(Tokens.TEXT_TERTIARY)
                        .maxLines(1)
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(this.checkedText(row))
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.TEXT_TERTIARY)
                    .margin({ right: 8 })
                  this.statusChip(row.displayStatus(), diagStatusLabel(row.displayStatus()))
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }, (row: ServiceHealthRow) => row.id + '_' + row.status)
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .margin({ top: 8 })
            .backgroundColor(Tokens.CARD)
            .borderRadius(Tokens.RADIUS_CARD)

            if (this.analyses.length > 0) {
              Text('AI 分析')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
                .width('100%')
                .margin({ top: 14 })

              Column() {
                ForEach(this.analyses, (row: DiagAnalysis) => {
                  this.checkRow(row)
                }, (row: DiagAnalysis) => row.id + '_' + row.ts)
              }
              .width('100%')
              .padding({ left: 14, right: 14 })
              .margin({ top: 8 })
              .backgroundColor(Tokens.CARD)
              .borderRadius(Tokens.RADIUS_CARD)
            }

            if (this.repairs.length > 0) {
              Text('修复任务')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Bold)
                .fontColor(Tokens.TEXT_PRIMARY)
                .width('100%')
                .margin({ top: 14 })

              Column() {
                ForEach(this.repairs, (task: RepairTask) => {
                  Row() {
                    Text(task.action.length > 0 ? task.action : task.id)
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.TEXT_PRIMARY)
                      .layoutWeight(1)
                      .maxLines(1)
                    Text(task.status)
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.TEXT_TERTIARY)
                  }
                  .width('100%')
                  .padding({ top: 6, bottom: 6 })
                }, (task: RepairTask) => task.id + '_' + task.status)
              }
              .width('100%')
              .padding({ left: 14, right: 14 })
              .margin({ top: 8, bottom: 16 })
              .backgroundColor(Tokens.CARD)
              .borderRadius(Tokens.RADIUS_CARD)
            }
          }
          .width('100%')
          .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 24 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Tokens.BG)
  }
}

function pad2(value: number): string {
  return value < 10 ? '0' + value : '' + value;
}
