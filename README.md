# GrokBot Soft-Pointer (Optimized 64×64)

针对 Windows 系统卡顿与边缘毛边问题优化后的 **GrokBot Soft-Pointer** 鼠标指针包。

## 优化内容

1. **大幅瘦身（61.99 MB → 18.31 MB）**：
   - 将默认箭头 `Motions/normal-cycle.ani` 从 40.11 MB（1,361 帧 / 45.4 秒）裁剪到第 389 帧自然循环点（约 13 秒，**6.30 MB**），显著降低 Windows 切换与驻留光标时的卡顿。
   - 仅保留原生最高清晰度 **`64×64`** 位图，移除冗余低分辨率档位。
2. **修复边缘毛边（Premultiplied Alpha）**：
   - 修正 `.ani` 帧中 `R/G/B > Alpha` 的非预乘半透明边缘像素，消除 Windows DWM 合成时的白边/溢色光晕。
3. **附带优化脚本**：
   - 包含 [`optimize_ani.py`](optimize_ani.py)，可按需重新生成 `32` / `48` / `64` px 版本。

## 安装方法

1. 下载并完整解压本仓库。
2. 双击运行 `Install.cmd`，按 `1` 应用指针方案（按 `2` 可一键恢复安装前的系统指针）。
3. 建议在 **Windows 设置 → 辅助功能 → 鼠标指针和触控** 中将指针大小设为 **3（64px）** 以匹配原生 `64×64` 分辨率，避免系统缩放模糊。

## 版权与来源

- 基于 [blessonism/grok-icon-study](https://github.com/blessonism/grok-icon-study)（`b7e6cd48db4eeba13271c653c38e1ad0f48037b4`）。
- 角色与预设归 xAI / 相应权利人所有，仅供个人学习使用。
