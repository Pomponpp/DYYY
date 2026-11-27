//
//  DetailRowPolicyTests.c
//  行高策略回归：详情页行高必须把"原生压缩高"映射到"撑高目标"（iPhone 13 Pro Max
//  上 843 → 926），让表高与行高同源；特殊行与非法输入一律透传。
//  纯 C，宿主机 gcc 可直接编译运行。
//
#include "../DYYYDetailRowPolicy.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int failures = 0;

static void expectAnswer(const char *name, double got, double want) {
    if (isnan(want) ? !isnan(got) : fabs(got - want) > 0.0001) {
        printf("FAIL %s: got %.1f, want %.1f\n", name, got, want);
        failures++;
    } else {
        printf("PASS %s\n", name);
    }
}

int main(void) {
    const double NAN_H = NAN;
    // 主场景（iPhone 13 Pro Max 真机）：原高 843 已记录、表已撑到 926，
    // 原生询问 843 —— 必须答 926，否则表 926 / 行 843 留下 83 空档。
    expectAnswer("compressed native maps to stretched target",
                 DYYYDetailRowHeightAnswer(1, 1, 843, 926, 843, NAN_H, 926), 926);
    // 已钉住目标：同样答目标。
    expectAnswer("pinned target wins",
                 DYYYDetailRowHeightAnswer(1, 1, 843, 926, 843, 926, 926), 926);
    // 首建行早于撑高：原高未知，按窗口高兜底（843 是满屏减去底栏）。
    expectAnswer("first build before stretch falls back to window",
                 DYYYDetailRowHeightAnswer(1, 1, 843, 843, NAN_H, NAN_H, 926), 926);
    // 滚动容器侧拿不到表：表高未知，同样按窗口高兜底。
    expectAnswer("container without table falls back to window",
                 DYYYDetailRowHeightAnswer(1, 1, 843, NAN_H, NAN_H, NAN_H, 926), 926);
    // 幂等：已经答过 926，再问还是 926。
    expectAnswer("already stretched stays idempotent",
                 DYYYDetailRowHeightAnswer(1, 1, 926, 926, 843, NAN_H, 926), 926);
    // 护栏：开关关闭时透传。
    expectAnswer("disabled passes native through",
                 DYYYDetailRowHeightAnswer(0, 1, 843, 926, 843, NAN_H, 926), 843);
    // 护栏：非详情表透传。
    expectAnswer("non-detail table passes through",
                 DYYYDetailRowHeightAnswer(1, 0, 843, 926, 843, NAN_H, 926), 843);
    // 护栏：特殊行（远小于半窗）透传，不得被撑成屏高。
    expectAnswer("special short row passes native through",
                 DYYYDetailRowHeightAnswer(1, 1, 100, 926, 843, NAN_H, 926), 100);
    // 护栏：非法输入透传。
    expectAnswer("invalid native passes through",
                 DYYYDetailRowHeightAnswer(1, 1, -5, 926, 843, NAN_H, 926), -5);
    // 护栏：差值超过底栏上限（>160）不属于"满屏减底栏"，透传。
    expectAnswer("oversized gap is not a bottom-bar compression",
                 DYYYDetailRowHeightAnswer(1, 1, 500, NAN_H, NAN_H, NAN_H, 926), 500);
    // 横屏窗口（原生行高已等于窗口高）：幂等返回窗口高。
    expectAnswer("landscape equal heights pass through",
                 DYYYDetailRowHeightAnswer(1, 1, 414, 414, 414, NAN_H, 414), 414);

    if (failures) {
        printf("%d test(s) failed\n", failures);
        return 1;
    }
    printf("all row policy tests passed\n");
    return 0;
}
