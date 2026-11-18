import { describe, it, expect } from '@ohos/hypium';
import { FitRecsRepository } from '../main/ets/data/fitrecs/FitRecsRepository';
import { FitRecord } from '../main/ets/features/fit/FitModels';
import { FakeApi } from './support/FakeApi';

export default function fitRecsTest() {
  describe('FitRecsRepository', () => {
    it('renames_record', 0, async () => {
      const api: FakeApi = new FakeApi();
      const repo: FitRecsRepository = new FitRecsRepository(api, () => '3260799999');
      const record: FitRecord = new FitRecord();
      record.id = 'f1';
      record.ts = 1794670584149;
      record.name = '旧名字';
      const ok = await repo.rename(record, ' 新名字 ');
      expect(ok.ok).assertTrue();
      expect(api.patchPaths[0]).assertEqual('fitrecs?id=eq.f1');
      expect(api.patchBodies[0].indexOf('新名字') > 0).assertTrue();
      const empty = await repo.rename(new FitRecord(), 'x');
      expect(empty.ok).assertTrue();
      const noName = await repo.rename(record, '   ');
      expect(noName.ok).assertTrue();
      api.failPosts = true;
      const bad = await repo.rename(record, 'x');
      expect(bad.ok).assertFalse();
    });
  });
}
