import { Blob, JsonBlob } from '../sync/JsonBlob';

/**
 * 班级名单一行（`POST rpc/class_members` → `[{seat,sid,name,role,badge,is_admin}]`）。
 *
 * 契约：ENDPOINTS.md E2；服务端已过滤 `is_test` 测试身份，班级名单约 70 人。
 * 隐私：`sid` 只用于云端内部键与个人数据归属，**页面不显示学号**。
 */
export class ClassMember {
  seat: number = 0;
  sid: string = '';
  name: string = '';
  role: string = '';
  badge: string = '';
  isAdmin: boolean = false;

  constructor(seat: number = 0, sid: string = '', name: string = '', role: string = '',
    badge: string = '', isAdmin: boolean = false) {
    this.seat = seat;
    this.sid = sid;
    this.name = name;
    this.role = role;
    this.badge = badge;
    this.isAdmin = isAdmin;
  }

  /** 是否班委：契约里「role 非空」即班委（badge=班委 是展示徽章）。 */
  isCommittee(): boolean {
    return this.role.trim().length > 0;
  }

  static fromJson(obj: Blob): ClassMember | undefined {
    const seat: number = JsonBlob.asNumber(JsonBlob.get(obj, 'seat'), 0);
    const name: string = JsonBlob.asString(JsonBlob.get(obj, 'name'), '').trim();
    if (seat <= 0 || name.length === 0) {
      return undefined;
    }
    return new ClassMember(
      Math.round(seat),
      JsonBlob.asString(JsonBlob.get(obj, 'sid'), '').trim(),
      name,
      JsonBlob.asString(JsonBlob.get(obj, 'role'), '').trim(),
      JsonBlob.asString(JsonBlob.get(obj, 'badge'), '').trim(),
      JsonBlob.asBoolean(JsonBlob.get(obj, 'is_admin'), false)
    );
  }

  toJson(): Blob {
    const out: Blob = {
      'seat': this.seat,
      'sid': this.sid,
      'name': this.name,
      'role': this.role,
      'badge': this.badge,
      'is_admin': this.isAdmin
    };
    return out;
  }
}

/** 团员名单模型（`POST rpc/class_league` → `{ok:true,count,seats:[{seat,name}]}`）。 */
export class LeagueMember {
  seat: number = 0;
  name: string = '';

  constructor(seat: number = 0, name: string = '') {
    this.seat = seat;
    this.name = name;
  }

  toJson(): Blob {
    const out: Blob = { 'seat': this.seat, 'name': this.name };
    return out;
  }
}

/** 名单展示条目（**不含学号**，满足隐私红线）。 */
export class MemberEntry {
  seat: number = 0;
  name: string = '';
  badge: string = '';

  constructor(seat: number = 0, name: string = '', badge: string = '') {
    this.seat = seat;
    this.name = name;
    this.badge = badge;
  }
}
