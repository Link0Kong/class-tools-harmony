export class TimetableFocus {
  time: number;
  name: string;
  room: string;
  period: number;

  constructor(time: number, name: string = '', room: string = '', period: number = 0) {
    this.time = time;
    this.name = name;
    this.room = room;
    this.period = period;
  }
}

