//
//  DYYYDetailRowPolicy.c
//  41.2 统一行高策略：详情页行高完全交还抖音原生（843），
//  全屏视觉由 DYYYFullscreenCoordinator 的容器撑满补偿负责。
//
//  历史：41.1 重构已确定此方向，但遗留回答路径在表撑高后仍答 926，
//  与抖音内部 843 写入逐帧互斥（实测一秒 46 次交替），cell 几何震荡
//  传导到互动层/文案/进度条，表现为详情页上下错位、进度条拖动跳动。
//  本函数是行高询问的唯一决策点：任何输入都透传原生值，杜绝拔河。
//  保留参数签名，供后续版本如需切换策略时单点修改并有测试锚点。
//

#include "DYYYDetailRowPolicy.h"

double DYYYDetailRowHeightAnswer(int enabled, int isDetail,
                                 double nativeHeight, double tableHeight,
                                 double originalHeight, double pinnedHeight,
                                 double windowHeight) {
    (void)enabled;
    (void)isDetail;
    (void)tableHeight;
    (void)originalHeight;
    (void)pinnedHeight;
    (void)windowHeight;
    return nativeHeight;
}
