import { common } from '@kit.AbilityKit';

/**
 * 在 ohosTest 中保存 TestAbility 的上下文，
 * 供测试用例调用 request.downloadFile 等需要 BaseContext 的接口。
 */
export class TestContext {
  static abilityContext: common.UIAbilityContext | null = null;
}
