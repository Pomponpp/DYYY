//
//  DetailRowPolicyTests.c
//  行高策略回归：详情页行高必须一律透传原生值（843），
//  任何情况下不得答出撑高值（926）——那是 41.2 错位与进度条跳动的根因。
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
    // 拔河场景（41.2 真机日志复现）：表已撑高 926、原高 843 已记录，
    // 原生询问 843。必须继续答 843，不得答 926。
    expectAnswer("tug-of-war: stretched table keeps native row",
                 DYYYDetailRowHeightAnswer(1, 1, 843, 926, 843, NAN_H, 926), 843);
    // 首次建行早于撑高：原高未记录，也不得用窗口高顶替原生行高。
    expectAnswer("first build before stretch keeps native row",
                 DYYYDetailRowHeightAnswer(1, 1, 843, 843, NAN_H, NAN_H, 926), 843);
    // 撑高目标已钉住（pinned=926）：仍透传原生。
    expectAnswer("pinned target does not override native row",
                 DYYYDetailRowHeightAnswer(1, 1, 843, 926, 843, 926, 926), 843);
    // 护栏：开关关闭时透传。
    expectAnswer("disabled passes native through",
                 DYYYDetailRowHeightAnswer(0, 1, 843, 926, 843, NAN_H, 926), 843);
    // 护栏：特殊行（远小于半窗）透传。
    expectAnswer("special short row passes native through",
                 DYYYDetailRowHeightAnswer(1, 1, 100, 926, 843, NAN_H, 926), 100);
    // 护栏：非法输入透传。
    expectAnswer("invalid native passes through",
                 DYYYDetailRowHeightAnswer(1, 1, -5, 926, 843, NAN_H, 926), -5);
    // 横屏窗口（843 原生 == 窗口高）：透传。
    expectAnswer("landscape equal heights pass through",
                 DYYYDetailRowHeightAnswer(1, 1, 414, 414, 414, NAN_H, 414), 414);

    if (failures) {
        printf("%d test(s) failed\n", failures);
        return 1;
    }
    printf("all row policy tests passed\n");
    return 0;
}
