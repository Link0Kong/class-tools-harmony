import { AppGlobal } from './AppGlobal';
import { AuthRepository } from '../data/auth/AuthRepository';
import { HttpClient } from '../data/net/HttpClient';
import { SessionStore } from '../data/session/SessionStore';
import { UserdataRepository } from '../data/sync/UserdataRepository';
import { FileUserdataLocalStore } from '../data/sync/UserdataLocalStore';
import { MarksRepository, FileMarksLocalStore } from '../data/marks/MarksRepository';
import { ClassMembersRepository, FileClassMemberCache } from '../data/member/ClassMembersRepository';
import { ClassLeagueRepository } from '../data/member/ClassLeagueRepository';
import { PreferencesVisitsStore, VisitsReporter } from '../data/visits/VisitsReporter';
import { VisitsRepository } from '../data/visits/VisitsRepository';
import { FitRecsRepository } from '../data/fitrecs/FitRecsRepository';
import { HomeworkRepository } from '../data/homework/HomeworkRepository';
import { NoticesRepository } from '../data/notices/NoticesRepository';
import { TimetableRepository, TtResult, TtSource } from '../data/timetable/TimetableRepository';
import { TimetableLoginRepository } from '../data/timetable/TimetableLoginRepository';
import { PowerRepository } from '../data/power/PowerRepository';
import { VoteRepository } from '../data/vote/VoteRepository';
import { PptRepository } from '../data/ppt/PptRepository';
import { DiagRepository } from '../data/diag/DiagRepository';
import { CloudSpaceRepository } from '../data/cloudspace/CloudSpaceRepository';
import { Blob, JsonBlob } from '../data/sync/JsonBlob';

/**
 * 数据层单例装配（手工依赖注入，不引第三方容器）。
 *
 * `currentSid` / `currentName` / `currentToken` 由根页面在登录/退出时维护；各仓库通过闭包读取，
 * 避免仓库持有会话对象。`currentToken` 只用于请求头（`X-Device-Id` 等），**不放日志、不落盘**。
 */
export class Services {
  static currentSid: string = '';
  static currentName: string = '';
  /** 当前身份是否管理员（用于通知 audience 的客户端兜底）。 */
  static currentIsAdmin: boolean = false;
  /** 班级 token（身份会话凭据）：只供请求头使用，禁止打印/持久化到日志或业务数据。 */
  static currentToken: string = '';

  static readonly api: HttpClient = new HttpClient();
  static readonly sessionStore: SessionStore = new SessionStore();
  static readonly auth: AuthRepository = new AuthRepository(Services.api);

  private static userdataGeneration: number = 0;
  private static userdataRepo: UserdataRepository = new UserdataRepository(
    Services.api, new FileUserdataLocalStore(() => ''), () => '');

  static get userdata(): UserdataRepository {
    return Services.userdataRepo;
  }

  /** 相同账号重新核验也启动新代次；旧仓储不再接触新会话的请求或文件桶。 */
  static startUserdataSession(sid: string): UserdataRepository {
    Services.userdata.endSession();
    const generation = ++Services.userdataGeneration;
    const owner = (): string => generation === Services.userdataGeneration ? sid : '';
    Services.userdataRepo = new UserdataRepository(Services.api, new FileUserdataLocalStore(owner), owner);
    return Services.userdata;
  }

  private static marksSid: string = '';
  private static marksRepo: MarksRepository | undefined = undefined;
  static get marks(): MarksRepository {
    const sid = Services.currentSid;
    if (!Services.marksRepo || Services.marksSid !== sid) {
      Services.marksSid = sid;
      Services.marksRepo = new MarksRepository(Services.api, () => Services.currentSid === sid ? sid : '',
        new FileMarksLocalStore(() => sid));
    }
    return Services.marksRepo;
  }

  static readonly members: ClassMembersRepository = new ClassMembersRepository(
    Services.api,
    new FileClassMemberCache(),
    () => Services.currentSid);

  static readonly league: ClassLeagueRepository = new ClassLeagueRepository(
    Services.api,
    () => Services.currentSid);

  static readonly fitRecs: FitRecsRepository = new FitRecsRepository(
    Services.api,
    () => Services.currentSid);

  private static homeworkSid: string = '';
  private static homeworkRepo: HomeworkRepository | undefined = undefined;
  static get homework(): HomeworkRepository {
    const sid = Services.currentSid;
    if (!Services.homeworkRepo || Services.homeworkSid !== sid) {
      Services.homeworkSid = sid;
      const dir = AppGlobal.context?.filesDir;
      const path = dir && sid ? dir + '/homework_' + encodeURIComponent(sid) + '.json' : '';
      Services.homeworkRepo = new HomeworkRepository(Services.api, () => Date.now(), undefined, path);
    }
    return Services.homeworkRepo;
  }

  static readonly notices: NoticesRepository = new NoticesRepository(
    Services.api,
    () => Date.now(),
    10 * 60 * 1000,
    () => Services.currentSid,
    () => Services.currentIsAdmin);

  static readonly power: PowerRepository = new PowerRepository(Services.api);

  static readonly vote: VoteRepository = new VoteRepository(Services.api);

  static readonly ppt: PptRepository = new PptRepository(Services.api);

  static readonly diag: DiagRepository = new DiagRepository(Services.api);

  static readonly timetable: TimetableRepository = new TimetableRepository(
    Services.api,
    () => JsonBlob.asBlob(JsonBlob.get(Services.userdata.currentSections(), 'tt')));

  /** 用户手动刷新工作台或课表时，先接收其他设备对个人课表的导入或清除。 */
  static async loadTimetableForView(force: boolean): Promise<TtResult> {
    if (force) {
      const userdata = Services.userdata;
      await userdata.pull(true);
      if (userdata !== Services.userdata) return new TtResult(false, undefined, false, TtSource.PUBLIC, '身份已切换');
    }
    return Services.timetable.load(force);
  }

  static readonly login: TimetableLoginRepository = new TimetableLoginRepository(Services.api);

  /** 文件传输 / 临时云空间（ECS drop v2.2；token 只在 X-Device-Id 请求头）。 */
  static readonly cloudspace: CloudSpaceRepository = new CloudSpaceRepository(
    () => Services.currentToken);

  static readonly visits: VisitsReporter = new VisitsReporter(
    Services.api,
    new PreferencesVisitsStore(),
    () => Services.currentSid,
    () => Services.currentName);

  /** 访问统计读取（仅管理员；页面在非管理员时不调用）。 */
  static readonly visitsRepository: VisitsRepository = new VisitsRepository(Services.api);
}
