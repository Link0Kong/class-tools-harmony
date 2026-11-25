import { Services } from '../../app/Services';
import { Tokens } from '../theme/Tokens';

@Component
export struct RosterSearchBox {
  @State private input: string = '';
  private revision: number = 0;
  onFilter: (text: string, seats: number[]) => void = () => {};

  aboutToDisappear(): void { this.revision++; }

  private async submit(): Promise<void> {
    const text: string = this.input;
    const revision: number = ++this.revision;
    const seats: number[] = await Services.members.searchSeats(text);
    if (revision === this.revision) this.onFilter(text, seats);
  }

  build() {
    Row({ space: 6 }) {
      TextInput({ text: this.input, placeholder: '搜索姓名、座号或职务' })
        .layoutWeight(1).height(42).fontSize(Tokens.F_LABEL)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.revision++;
          this.input = value;
          this.onFilter(value, []);
        })
        .onSubmit(() => { this.submit(); })
      Button('搜索').fontSize(Tokens.F_LABEL).fontColor('#285E54')
        .backgroundColor(Tokens.TINT_TEAL).height(40).onClick(() => { this.submit(); })
    }.width('100%')
  }
}
