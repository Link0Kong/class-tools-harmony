import { describe, expect, it } from '@ohos/hypium';
import { DeskFeed, DeskLine, deskContent } from '../main/ets/forms/DeskContent';
import { Course } from '../main/ets/data/timetable/TimetableModels';

export default function deskFormsTest() {
  describe('DeskForms', () => {
    const now = new Date(2026, 10, 23, 8, 30).getTime();
    it('hides previous data from signed-out forms', 0, () => {
      const feed = new DeskFeed();
      feed.notices.push(new DeskLine());
      const result = deskContent('nt', feed, 4, 3, now);
      expect(result.rows.length).assertEqual(0);
      expect(result.empty).assertEqual('登录后查看');
      expect(result.palette).assertEqual(3);
    });

    it('removes imported and expired assignments before counting or clipping rows', 0, () => {
      const feed = new DeskFeed();
      feed.sid = '9999';
      feed.homeworkAt = now;
      feed.taskAt = now;
      const old = new DeskLine();
      old.homeworkId = 'old';
      old.dueAt = now - 4 * 86400000;
      const imported = new DeskLine();
      imported.homeworkId = 'completed-import';
      const active = new DeskLine();
      active.title = '作业 · 完成实验报告';
      active.homeworkId = 'hw-active';
      active.dueAt = now + 3600000;
      active.toolId = 'hw';
      const task = new DeskLine();
      task.title = '预约自习室';
      task.taskId = 't-1';
      task.toolId = 'hw';
      feed.assignments = [old, imported, active];
      feed.imported = [imported.homeworkId];
      feed.tasks = [task];
      const compact = deskContent('hw', feed, 2, 0, now);
      expect(compact.summary).assertEqual('1 待办 · 1 作业');
      expect(compact.rows.length).assertEqual(1);
      expect(compact.rows[0].homeworkId).assertEqual('hw-active');
      expect(deskContent('hw', feed, 3, 0, now).rows[1].taskId).assertEqual('t-1');
    });

    it('recomputes the current course on system refresh', 0, () => {
      const feed = new DeskFeed();
      feed.sid = '9999';
      feed.term = '2026-11-23';
      const course = new Course();
      course.name = '实验课';
      course.room = '教学楼 203';
      feed.courses = [course];
      const active = deskContent('tt', feed, 2, 0, now);
      expect(active.heading).assertEqual('正在上课');
      expect(active.rows[0].detail.includes('教学楼 203')).assertTrue();
      expect(deskContent('tt', feed, 2, 0, now + 3600000).heading.includes('下一节')).assertTrue();
    });

    it('shows the ongoing class and the following bell as separate rows', 0, () => {
      const feed = new DeskFeed();
      feed.sid = '9999';
      feed.term = '2026-11-23';
      const double = new Course();
      double.name = '连堂实验';
      double.end = 2;
      const later = new Course();
      later.name = '英语';
      later.start = later.end = 3;
      feed.courses = [double, later];
      const card = deskContent('tt', feed, 3, 0, now);
      expect(card.heading).assertEqual('正在上课');
      expect(card.rows.length).assertEqual(2);
      expect(card.rows[0].detail.includes('08:10–08:50')).assertTrue();
      expect(card.rows[1].detail.includes('09:00–09:40')).assertTrue();
      const inBreak = deskContent('tt', feed, 3, 0, new Date(2026, 10, 23, 8, 50).getTime());
      expect(inBreak.heading.includes('下一节')).assertTrue();
      expect(inBreak.rows[1].title).assertEqual('英语');
    });

    it('links workbench notices to their occurrence and labels cached notices', 0, () => {
      const feed = new DeskFeed();
      feed.sid = '9999';
      feed.noticeAt = now - 7200000;
      const notice = new DeskLine();
      notice.noticeId = 'event@occ:1';
      notice.toolId = 'nt';
      feed.pendingNotices = [notice];
      feed.notices = [notice];
      expect(deskContent('home', feed, 4, 0, now).rows[0].noticeId).assertEqual('event@occ:1');
      expect(deskContent('nt', feed, 4, 0, now).summary.includes('上次同步')).assertTrue();
    });
  });
}
