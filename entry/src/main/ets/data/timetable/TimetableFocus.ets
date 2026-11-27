import { Course, SessionInfo } from './TimetableModels';

export class TimetableFocus {
  time: number;
  name: string;
  room: string;
  period: number;
  start: number;
  end: number;
  teacher: string;

  constructor(time: number, name: string = '', room: string = '', period: number = 0,
    start: number = 0, end: number = 0, teacher: string = '') {
    this.time = time;
    this.name = name;
    this.room = room;
    this.period = period;
    this.start = start;
    this.end = end;
    this.teacher = teacher;
  }

  static fromSession(cls: SessionInfo): TimetableFocus {
    return new TimetableFocus(cls.startAt, cls.name, cls.fullRoom || cls.room, cls.period, cls.start, cls.end, cls.teacher);
  }

  static reminderKey(cls: SessionInfo): string {
    return 'cls:' + JSON.stringify([String(cls.startAt), cls.name, cls.fullRoom || cls.room,
      String(cls.start), String(cls.end), cls.teacher]);
  }

  static matches(focus: TimetableFocus, course: Course): boolean {
    return (course.name.trim() || '课程') === focus.name && course.room.trim() === focus.room &&
      (!focus.teacher || course.teacher.trim() === focus.teacher) && focus.period >= course.start &&
      focus.period <= course.end && (!focus.start || course.start === focus.start) && (!focus.end || course.end === focus.end);
  }
}
