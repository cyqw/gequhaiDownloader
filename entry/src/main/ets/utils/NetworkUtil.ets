/**
 * 网络类型相关的纯函数工具。
 *
 * 这里不依赖任何系统 Kit，便于在 ohosTest 中直接对逻辑做单元测试。
 * 取值与 @ohos.net.connection 的 NetBearType 保持一致：
 *   BEARER_CELLULAR = 0, BEARER_WIFI = 1, BEARER_BLUETOOTH = 2,
 *   BEARER_ETHERNET = 3, BEARER_VPN = 4
 */

export type NetworkKind = 'wlan' | 'mobile' | 'none' | 'unknown';

/** 开始下载前的决策：直接开始 / 需要询问用户 / 等待 WLAN。 */
export type StartDecision = 'start' | 'prompt' | 'wait';

/** 网络切换时需要执行的动作。 */
export type TransitionAction = 'pause' | 'resume' | 'none';

export const BEARER_CELLULAR: number = 0;
export const BEARER_WIFI: number = 1;
export const BEARER_BLUETOOTH: number = 2;
export const BEARER_ETHERNET: number = 3;
export const BEARER_VPN: number = 4;

/**
 * 由 NetCapabilities.bearerTypes 推断当前网络类型。
 * - 只要包含 WLAN/以太网即视为 wlan（优先走不计流量的网络）；
 * - 仅包含蜂窝网络时视为 mobile；
 * - 仅包含蓝牙/VPN 等其它承载时视为 unknown；
 * - 空列表视为 none（无网络）。
 */
export function networkKindFromBearerTypes(bearerTypes: number[]): NetworkKind {
  if (!bearerTypes || bearerTypes.length === 0) {
    return 'none';
  }
  let hasWlan = false;
  let hasMobile = false;
  let hasOther = false;
  for (let i = 0; i < bearerTypes.length; i++) {
    const t = bearerTypes[i];
    if (t === BEARER_WIFI || t === BEARER_ETHERNET) {
      hasWlan = true;
    } else if (t === BEARER_CELLULAR) {
      hasMobile = true;
    } else {
      hasOther = true;
    }
  }
  if (hasWlan) {
    return 'wlan';
  }
  if (hasMobile) {
    return 'mobile';
  }
  if (hasOther) {
    return 'unknown';
  }
  return 'none';
}

/**
 * 开始下载前的决策：
 * - 移动网络且用户尚未允许使用移动数据 -> prompt（需要询问）；
 * - 其它情况（WLAN/无网/未知）-> start。
 * 返回 wait 用于调用方在用户选择“等待 WLAN”后显式标记等待状态。
 */
export function decideStart(kind: NetworkKind, allowMobile: boolean): StartDecision {
  if (kind === 'mobile') {
    return allowMobile ? 'start' : 'prompt';
  }
  return 'start';
}

/**
 * 网络切换动作：
 * - WLAN -> 移动网络：暂停（避免偷跑流量）
 * - 移动网络 -> WLAN：恢复
 * - 其它组合：不处理
 */
export function networkTransitionAction(prev: NetworkKind, next: NetworkKind): TransitionAction {
  if (prev === 'wlan' && next === 'mobile') {
    return 'pause';
  }
  if (prev === 'mobile' && next === 'wlan') {
    return 'resume';
  }
  return 'none';
}
