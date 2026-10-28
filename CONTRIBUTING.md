# 两人协作

本仓库只包含加速器源码、Golden、测试、实验室入口和文档。不提交工艺库、Synopsys 软件、旧框架结果、运行目录或大波形。

## 第一次使用

远端创建后，将仓库克隆到自己的工作目录。Python 依赖安装：

```sh
python -m pip install -r requirements.txt
```

本地验证还需要 Icarus；结构检查需要 Yosys。Windows 支持 `EDA_OSS_CAD_SUITE`，Linux 支持 PATH。

```sh
python scripts/run_tests.py
python scripts/test_softmax.py
python scripts/synth_check.py
```

VCS 默认测试不需要 NumPy，执行 `bash lab/run_vcs.sh`。DC 执行 `dc_shell -f lab/dc_synth.tcl`；需将实验室工艺资料单独放在相邻 `sm2/ref/`，或设置 `T2_REF`。工艺文件不通过 Git 分发。

## 分工和合并

| 人员 | 主要修改范围 | 完成标准 |
| --- | --- | --- |
| 设计 | rtl/、lab/、架构文档 | RTL 回归通过，接口/定点规则有更新；实验室结果如实记录 |
| 验证 | scripts/、tests/、验证文档 | 覆盖边界、协议、复位及逐阶段正确性，测试能复现 |

两人都从 main 拉取分支，例如 design/pe 或 verify/coverage。每次任务开始先同步 main，各自在分支提交，通过 Pull Request 合并。修改 Golden 或接口时必须双方复核，不能仅为通过测试而修改预期值。

```sh
git switch main
git pull --ff-only
git switch -c design/your-task
# 修改并运行相关测试
git add rtl docs
git commit -m "Describe the concrete change"
git push -u origin HEAD
```

验证同学使用 verify/your-task 分支。不要直接覆盖对方文件，不提交密码、token 或本机环境密钥。没有检查通过时，提交说明中记录失败与未完成项。

## 实验结果怎么共享

build/ 与 lab_runs/ 忽略。原始日志、波形、GDS 用共享网盘或实验室目录保存；在 docs/results/ 写本次配置、工具版本、通过范围、结果摘要和原始文件位置，再提交小型摘要。没有实际执行的流程不得标为通过。

## 发布到远端

目前建立的是本地 Git 仓库，没有线上 URL，也未推送。确定 GitHub/Gitee 和目标账户后创建空仓库，不要自动生成 README，然后执行：

```sh
git remote add origin <你创建的仓库地址>
git push -u origin main
```

在平台邀请另一位同学为协作者。仓库初期建议设为私有；即使是私有仓库，工艺资料也继续留在仓库外。

没有远端时，可以分享同级 `eda_t2_accelerator.bundle`，对方执行 `git clone eda_t2_accelerator.bundle eda_t2_accelerator`。bundle 只是当前历史快照，后续持续协作仍建议配置远端。
