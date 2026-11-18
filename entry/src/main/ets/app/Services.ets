import { AuthRepository } from '../data/auth/AuthRepository';
import { HttpClient } from '../data/net/HttpClient';
import { SessionStore } from '../data/session/SessionStore';
import { UserdataRepository } from '../data/sync/UserdataRepository';
import { FileUserdataLocalStore } from '../data/sync/UserdataLocalStore';
import { MarksRepository, FileMarksLocalStore } from '../data/marks/MarksRepository';
import { ClassMembersRepository, FileClassMemberCache } from '../data/member/ClassMembersRepository';
import { ClassLeagueRepository } from '../data/member/ClassLeagueRepository';
import { PreferencesVisitsStore, VisitsReporter } from '../data/visits/VisitsReporter';
import { FitRecsRepository } from '../data/fitrecs/FitRecsRepository';
import { HomeworkRepository } from '../data/homework/HomeworkRepository';
import { NoticesRepository } from '../data/notices/NoticesRepository';
import { TimetableRepository } from '../data/timetable/TimetableRepository';
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

  static readonly userdata: UserdataRepository = new UserdataRepository(
    Services.api,
    new FileUserdataLocalStore(() => Services.currentSid),
    () => Services.currentSid);

  static readonly marks: MarksRepository = new MarksRepository(
    Services.api,
    () => Services.currentSid,
    new FileMarksLocalStore(() => Services.currentSid));

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

  static readonly homework: HomeworkRepository = new HomeworkRepository(Services.api);

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

  static readonly login: TimetableLoginRepository = new TimetableLoginRepository(Services.api);

  /** 文件传输 / 临时云空间（ECS drop v2.2；token 只在 X-Device-Id 请求头）。 */
  static readonly cloudspace: CloudSpaceRepository = new CloudSpaceRepository(
    () => Services.currentToken);

  static readonly visits: VisitsReporter = new VisitsReporter(
    Services.api,
    new PreferencesVisitsStore(),
    () => Services.currentSid,
    () => Services.currentName);
}
