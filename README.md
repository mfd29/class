# EDA 课设：题目二 Transformer 硬件加速器

更新：2026-10-28。

当前方向按用户要求从题目三改为题目二。旧目录 `../eda_t3_agent/` 保留作历史资料，不作为新题目交付物。课程原始要求见 `../EDA课设.md`。

## 新设计入口

- [Transformer加速器v0.1设计文档](docs/Transformer加速器v0.1设计文档.md)：端口、功能块、定点规则、状态、资源与新版硬件流程图。
- `rtl/`：INT8 单头注意力 + 两层 ReLU FFN 的可综合基线。
- `docs/架构与数值约定.md`：接口、精度、数据流、FSM、周期和范围声明。
- `scripts/run_tests.py`：Icarus 与 NumPy 全阶段逐元素自检。
- `scripts/test_softmax.py`：指数 LUT 和独立 Softmax 自检。
- `scripts/synth_check.py`：Yosys 结构检查，不作为工艺 PPA。
- `lab/run_vcs.sh`：实验室 VCS 默认配置运行入口，尚未在 VCS 执行。
- `lab/dc_synth.tcl`：独立输出目录的 DC 综合入口，尚未在 DC 执行。
- `docs/本地验证与实验室运行.md`：本地复现、实验室命令和当前验证结果。

旧 `sm2` 作为工艺和脚本参考保留；新 RTL 不覆盖原框架历史文件。以下“框架核查”描述的是原包状态。

## 当前核查结论

`../sm2_nortl.tar.gz` 已解压到 `../sm2/`。它提供可复用的工艺资料及旧版 Synopsys 流程，但不是放入 RTL 即可直接完成课设的工程。

已核实存在：

- `sm2/syn/rtl/`：目录为空，待放入新设计。
- `sm2/syn/scripts/`：DC 综合脚本及约束。
- `sm2/layout/scripts/`：ICC 布局、CTS、布线脚本。
- `sm2/fm/fm.tcl`：旧 Formality 脚本。
- `sm2/ref/db/sc_max.db`、`sc_min.db`：标准单元逻辑库；另有 IO、特殊单元和若干 SRAM 逻辑库。
- `sm2/ref/mw_lib/`：Milkyway 物理参考库。
- `sm2/ref/tech/cb13_6m.tf`、`sm2/ref/tlup/`：工艺文件和 max/min/typ TLU+。

逻辑库和物理库文件存在不代表已验证可用；仍需实验室工具读取并执行库一致性检查。

## 复用前必须修正的地方

| 文件 | 已发现的问题 | 接入要求 |
| --- | --- | --- |
| `syn/scripts/run_dc.tcl` | 读取不存在的 ECC256.v、mod256.v，顶层 ECC256，产物却命名 HDMI_ENCODER | 统一新顶层、RTL 文件清单及产物名 |
| `syn/scripts/run_dc.tcl` | 默认 `compile_ultra ... -scan` | 明确是否做 DFT；无扫描链方案时不能直接沿用 |
| `syn/scripts/top_constraints.tcl` | 注释写 100 MHz，实际 Tclk=50；时钟 clk、复位 rst_n 写死 | 按设计设置周期和单位，定义 I/O 时序及复位处理 |
| `layout/scripts/icc_setup.tcl` | DESIGN_NAME=HDMI_ENCODER | 与综合顶层统一；确认实验室提供 ICC 还是 ICC2 |
| `layout/scripts/run_icc.tcl` | 导入 HDMI_ENCODER.mapped.ddc，却选择 ECC256 | 统一顶层、输入网表和约束来源 |
| `layout/scripts/run_icc.tcl` | 开头会删除已有 MW_DESIGN_LIBRARY | 改成独立运行目录，避免覆盖已有工作 |
| `layout/scripts/run_icc.tcl` | 包含 `report_qorreport_qor`、多余 `-` 等可疑命令 | 在实验室版本逐阶段校正并保留日志 |
| `layout/scripts/run_icc.tcl` | 引脚按 *in*、*out* 匹配，电源及版图参数写死 | 按新设计真实端口、电压和规模重设 |
| `layout/scripts/run_icc.tcl` | 天线修复被关闭，有 verify_zrt_route，未见完整签核和 GDS 导出命令 | 补齐天线检查、最终导出、DRC/LVS；不能把路由检查直接写成签核通过 |
| `fm/fm.tcl` | setup 路径与实际目录不符，foreach 行有多余引号，仍读取 HDMI RTL | 修正路径、语法、SVF 和双方顶层；FM 是逻辑等价，不是版图 LVS |

`syn/rpt/area.rpt` 实际标注 Design=ECC256，日期为 2021-04-30。包内旧 rpt、mapped.ddc、mapped.v、SDF、SPEF 和 Milkyway 工作库仅是历史样例，不能用于本次加速器报告或截图。原始解压文件暂未改动。

## 题目二还缺什么

1. **架构与接口定义**：单头自注意力 Q/K/V 投影、QK 转置乘法、缩放、Softmax、加权 V，以及前馈网络；明确序列/隐藏维度、FFN 中间维度、激活函数、数据布局、存储和握手协议。
2. **加速器 RTL**：PE/MAC 阵列、可复用矩阵乘引擎、定点缩放/舍入/饱和、Softmax、FFN、控制 FSM、片上存储及读写接口。只有乘法器或矩阵乘阵列不覆盖完整要求。
3. **验证闭环**：Python/NumPy Golden Model、自检 Testbench、向量和误差标准、边界测试及端到端测试。需明确 INT8 与累加/Softmax 的内部精度，不能把所有中间结果都视为 INT8。
4. **约束和真实 PPA**：时钟、输入输出延迟、负载、角点；面积/寄存器数、setup/hold、违例和功耗报告；功耗需记录活动来源，无 SAIF/VCD 的估算要明确标注。
5. **后端交付**：floorplan → placement → CTS → routing → 最终网表/SDC/SPEF/GDS；匹配工艺的 GDS 层映射与单元版图数据、DRC/LVS 规则和可用验证工具需实验室确认。本次包内未检出明确的 GDS 文件或完整 DRC/LVS runset。
6. **性能及对比**：测试周期数、实际频率与吞吐量、核心/单元/存储面积、动态/静态功耗；开源参考设计、引用及同口径比较。尚未选定参考项目。

## 建议的第一版方案（待架构设计确认）

优先 INT8、较小 PE 阵列、分块和时分复用同一矩阵乘引擎，先跑小尺寸端到端验证，再扩展配置与边界。课程写的是序列长度不超过 64、隐藏维度不超过 256；最终支持范围需在报告中准确声明。

Softmax 用显式定义的定点近似并给出误差；FFN 包含两次线性变换和约定激活。存储若先用寄存器实现，应如实报告，不得把寄存器阵列算成 SRAM 宏；引入 SRAM 时需匹配逻辑库、物理库、模型和容量。

初版已实现 INT8、小型并行 PE、复用点积引擎及定点 Softmax；功能结果以 `build/test_summary.json` 和验证文档为准，尚无实验室 PPA 数值。

## 实验室环境待确认

- 已确定由用户在实验室实际操作；不依赖远程接入。
- 用户确认 ICC 可以启动；其余工具版本、许可与配套规则路径等后续实际运行再确认。
- 工艺资料是否允许用于本课程，是否有完整签核规则、GDS 导出资料、SRAM 仿真模型。
- GUI 可访问性：用于真实工具截图。当前 Windows PATH 未发现 dc_shell、icc_shell、pt_shell、fm_shell、vcs；这不等于实验室没有安装。

可在实验室 Linux 终端先执行以下只读检查，并回传文本（不要回传密码或许可证密钥）：

```sh
hostname
pwd
for tool in dc_shell icc_shell icc2_shell pt_shell fm_shell vcs verdi icv calibre; do
    command -v "$tool" || true
done
```

## 报告与截图验收清单

| 阶段 | 必留证据 |
| --- | --- |
| 功能验证 | Golden 对比通过日志，波形中输入/输出/握手，边界用例，周期数 |
| DC | 新顶层和工具版本，check_design/check_timing，面积/寄存器数、timing slack、功耗与活动假设 |
| ICC | floorplan、placement、CTS、最终路由版图；利用率、时钟树/偏斜、布线后面积、setup/hold、功耗 |
| PT | 最终网表+SDC+匹配角点 SPEF 的回读记录，max/min 时序及约束覆盖情况；功耗需相应功能许可及活动数据 |
| DRC/LVS | 使用的规则集、顶层、最终状态、违例数量与处理说明；与最终 GDS 对应 |
| 导出 | GDS、最终网表、SDC、SPEF 与日志；记录同一批次运行路径 |

截图必须来自新设计的真实工具运行，保留设计名、阶段、关键数字及可追溯日志。失败结果如实标记，不能用历史结果或制作的图表替代工具截图。

## 当前完成状态

- 已解压框架并完成文件级核查。
- 已建立题目二 RTL、NumPy Golden、自检脚本及架构文档，旧题目三保留。
- 已执行本地 RTL 功能验证和结构检查，详情见验证文档；D=256 的本机 Icarus 编译超时，不能记为通过。
- 已准备 VCS 和 DC 入口，等待用户在实验室执行；ICC 新设计流程、签核和截图仍未完成。
