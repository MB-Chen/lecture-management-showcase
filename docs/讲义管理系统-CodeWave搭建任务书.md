# 讲义管理系统 — CodeWave 搭建任务书（V3 课程组模型）

> 生成日期：2026-08-18
> 依据：《讲义管理系统-设计修订说明 V1.5.md》（课程组模型 + 五节点审批链）+ 《讲义管理系统-原型V3.html》
> 技术依据：CodeWave 官方文档（流程 2.0 / 数据表格树形模式 / 文件上传组件 / lcap process framework v1.10.0 流程逻辑库）
> 周期：**10 个工作日（MVP）**，每天含任务清单 / 交付物 / 验收标准
> 关联文件：《讲义管理系统-积压项清单.md》（本任务书未排入的事项入积压项）

---

## 〇、MVP 范围与目标

| 项 | 内容 |
|----|------|
| MVP 范围 | 7 页面（P1~P7）中优先 P1 讲义总览 / P2 提交申请 / P4 审批页 / P5 学院提交情况 / P6 教务总览；P3 提交历史、P7 流转记录同批完成（轻量） |
| 完成标志 | 教师提交（课程组+两级文件）→ 五节点审批（负责人→教秘→教务处处长只读→教学院长）→ 通过/驳回/重提/撤回/无需提交/拆组 全流程走通 |
| 不排入 | 鸿翼集成（V1.5）、权限同步/H5/分享（V2）、审计日志（最后）→ 见积压项清单 |

---

## 一、前置准备（D0，开工前确认）

| # | 事项 | 说明 | 依据 |
|---|------|------|------|
| 1 | 启用流程 2.0 | IDE 系统偏好设置开启（需平台 3.7+，建议 3.13+ 以使用流程逻辑依赖库）；**开启前备份应用** | 流程2.0 升级说明 |
| 2 | 引入流程逻辑依赖库 | `lcap process framework`（v1.10.0+）：launchProcess/approveTask/rejectTask/withdrawTask 等 | 流程逻辑使用说明 |
| 3 | 教务数据源直连 | 配置教务 MySQL 数据源（<内网地址·已脱敏>:6001），只读查询 csm_teaching_task / csm_teaching_teacher_map / tpm_approval_set / tpm_course_table / sys_teacher_info / sys_department_information / sys_academic_year | 已确认直连方案 |
| 4 | 用户体系 | LCAPUser.userName = "工号:姓名"（如 `20191012:张明`）；教务员工工号已导入平台（复用鸿翼同步结果） | V1.5 决策 |
| 5 | 枚举定义 | auditStatus（组级）：0 待课程负责人审核 / 1 待教学秘书审核 / 2 待教务处处长审核 / 3 待教学院长审批 / 4 已通过 / 5 已驳回 | V1.5 §1.4 |
| 6 | 🆕 **CodeWave 业务角色配置** | 在应用"用户与权限"或"业务角色管理"里建 5 个角色：`jygl_teacher`（教师）/ `jygl_course_leader`（课程负责人）/ `jygl_secretary`（教学秘书）/ `jygl_dean`（教学院长）/ `jygl_director`（教务处处长）；指派人员到角色（教师/负责人可考虑全员导入；教秘/院长/处长按学院/校级逐一指派）。**注意：业务角色是单值（primaryRole），教师兼负责人时按 primaryRole 优先级进入对应视图** | 取代积压项 P0 B-04 轻量映射表方案（§5.7 resolveUserRole 用 currentRole 直接判定） |

> 📌 **教务表查询范围说明（2026-08-18 核对确认）**：教务库共 10 张表，本系统仅需直连查询上表第 3 条的 **7 张**（csm_teaching_task / csm_teaching_teacher_map / tpm_approval_set / tpm_course_table / sys_teacher_info / sys_department_information / sys_academic_year）。其余 3 张**无需查询**：`csm_teaching_class_map`（行政班已由 csm_teaching_task.class_code_list 自带）、`tpm_course_replace_code`（课程替换业务不使用）、`sys_operation_log`（仅审计参考）。
> ⚠️ 搭建时注意：`csm_teaching_task.course_code`（bigint）与 `tpm_course_table.course_code`（varchar）类型不一致，配置数据源后先实测确认关联字段用 course_code 还是 id，勿按文档写死 join。

---

## 二、数据建模（D1）

### 2.1 实体清单（4 张，CodeWave 实体 = 自建表）

| 实体 | 关键字段 | 说明 |
|------|---------|------|
| **jygl_lecture_group** | academicYear / semester / courseCode / courseName / teachingCollege / leaderId / leaderName / teacherId / teacherName / title / description / version / processId / taskId / auditStatus(枚举) / curApprover / rejectReason / roundNo / itemCount / archiverName / isWithdrawn / withdrawBy / withdrawTime | 申请组主表，**流程 2.0 绑定实体**（绑定后不可改） |
| **jygl_lecture_group_item** | groupId / courseSelectionNumber / classCodeList / isUnsubmit / isInvalid / itemStatus / roundNo / splitGroupId | 选课号明细，数据真实颗粒度 |
| **jygl_material_file** | groupId / itemId(可空) / fileName / fileExt / fileSize / roundNo / hongyiFileId(必填) / hongyiFolderId / isDelete | itemId 空=课程级共享文件；非空=选课号专属文件 |
| **jygl_hy_folder_map** | level / pathKey / semester / collegeId / courseCode / courseSelectionNumber / folderId / parentFolderId | 鸿翼目录映射（V1.5 用，MVP 建结构） |

### 2.2 枚举：auditStatus（6 值）+ 明细标记

- 组级 `auditStatus`：0~5（见前置准备第 5 条）
- 明细级仅两个标记位：`isUnsubmit`（无需提交）、`isInvalid`（选课号已软删）——**不占 auditStatus**
- 撤回 = 组表 `isWithdrawn` 标记位（不占状态值、不增轮次）

### 2.3 关键约定

- 流程变量：`leaderName`（课程负责人 userName，"工号:姓名"）——负责人节点审批人
- 组版本展示 = `"v" + roundNo`

---

## 三、关键实现机制总览（先看这张表）

| 页面/能力 | 组件方案 | 关键逻辑 | 文档依据 |
|-----------|---------|---------|---------|
| P1 讲义总览（树形） | **数据表格·树形模式**（值字段 id / 子级值字段 children / 包含子级值字段 hasChildren；树型列=课程列） | `loadGroupTree`（服务端组装嵌套 List） | 数据表格.md；095.树形结构案例 |
| P2 提交页（树形多选） | 数据表格·树形模式 + **多选列 + 关联选中类型=父子双向关联选中** | `doSubmit`（校验→写组/明细/文件→launchProcess→回写 processId） | 数据表格.md；122.单选多选案例 |
| P2 文件两级上传 | **文件上传组件**（值=String、多文件上传开关；共享=普通区、专属=明细行内上传组件） | 上传后取文件 String 存 jygl_material_file | 文件上传.md；020.上传组件案例 |
| P4 审批页 | **流程表单 + 流程按钮 + 流程信息 + 流程记录 + 流程图**（全基于 taskId） | 节点审批人=**流程逻辑动态查人**（教秘/教学院长）；教务处节点数据权限=全只读；登录人权限视图= `currentRole.businessRoleName` | 流程组件.md；流程表单.md；流程按钮.md |
| 审批待办列表 | 任务箱组件（红点+跳转） + 自建列表页（getMyPendingTasks） | 待办按角色过滤（leaderId / teachingCollege / 全校）；角色判定= `resolveUserRole`（§5.7，依赖 `currentRole`） | 流程组件.md |</old_string><replace_all>false</replace_all>
| P5 学院提交情况 | 数据表格 + 统计卡 | `markUnsubmit` / `cancelUnsubmit`（明细级 isUnsubmit） | V1.5 §P5 |
| P6 教务总览 | 统计卡 + 数据表格 + 筛选表单 | `loadOverviewStat`（按学院聚合+各环节积压） | V1.5 §P6 |
| 驳回重提 | 开始节点审批页面（发起人重提） | `resubmit`：roundNo+1 → **submitTask**（原流程实例继续，process_id 不变；⚠️ 勿重新 launchProcess，会生成双实例） | 流程节点配置说明（开始节点需配审批页面）；流程逻辑使用说明 |
| 撤回 | 流程按钮·撤回 或 withdrawTask | 组表 isWithdrawn=1；不增轮次；⚠️ **平台限制：仅"提交后→负责人节点未处理前"可撤**（见 D8） | 流程逻辑使用说明；流程节点配置说明 |
| 拆组 | 服务端逻辑 | `splitGroup`：明细 splitGroupId→新组，新组独立走流程 | V1.5 §3.4 |
| 状态回写 | **流程事件（任务创建时/关闭时）+ 自动任务节点** | 用流程变量 curr.nodeParticipants/curr.nodeTitle/data 更新实体 auditStatus/curApprover/itemStatus/archiverName | 流程数据与实体数据的同步.md |

### ⚠️ 实施可行性关键约束（2026-08-18 codewave-brain 复查新增）

> 以下 3 条是本系统所有服务端逻辑（loadGroupTree/doSubmit/loadOverviewStat 等）的**平台硬约束**，D1 配数据源、D3 写逻辑前必须读：

| # | 平台约束 | 对本系统的影响 | 应对方案 |
|---|---------|---------------|---------|
| 1 | **SQL查询组件支持切换数据源**（可查教务库），但 **不支持跨数据源 SQL**（SQL查询.md：仅查单数据源） | loadGroupTree 不能一次 SQL 同时 join 教务库表 + 应用库组表 | 分两步：① SQL查询组件（切教务数据源）查教务 7 表聚合 → ② 实体查询组件查应用库 jygl_lecture_group/明细 → ③ 逻辑内存组装嵌套 List |
| 2 | **SQL查询组件只允许 SELECT**，禁止 DML/DDL（SQL查询.md） | doSubmit 写组/明细/文件**不能**用 SQL 语句 | 写操作全部用**实体增删改查组件**（CodeWave 自动生成的实体 CRUD 逻辑），SQL 组件仅用于教务只读查询 |
| 3 | **禁止字符串拼接动态 SQL**（MyBatis `#{}` 占位防注入；SQL查询.md） | 任务书旧思路"按条件拼 WHERE"不可行 | 动态条件用 SQL 组件内置的**动态SQL拼接**能力（变量条件式拼接，非字符串拼接），或多次查询后内存过滤 |
| 4 | **服务端逻辑支持事务**（系统偏好设置"新建逻辑默认开启事务"；逻辑属性面板"是否开启事务"开关） | doSubmit 写 3 表 + launchProcess 需原子 | doSubmit 服务端逻辑**开启事务**（异常自动回滚数据库操作）；launchProcess 属流程调用，注意事务边界 |
| 5 | 教务库**不可写**（只读直连 + 红线） | 无写教务需求，但审批人动态查人（findSecretaryByCollege）只读查教务 OK | - |

> 📌 对任务书 §5 伪代码的修正要求：5.1 loadGroupTree、5.3 审批人查人、5.7 resolveUserRole、5.8 loadOverviewStat 均为"教务查询 → 应用库查询 → 内存组装"三段式，写逻辑时按约束 1/2/3 落地。



---

## 四、10 个工作日排期

### 📅 D1：环境 + 数据建模 + 流程骨架

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 启用流程 2.0 + 引入 lcap process framework 依赖库 | 环境就绪 | 流程 2.0 菜单可用；流程逻辑可在服务端逻辑中调用 |
| 建 4 实体（含字段/枚举/索引） | 实体建模完成 | 字段与 V1.5 §3.2/3.3/3.5 一致；auditStatus 枚举 6 值 |
| 配置教务数据源直连 | 数据源可用 | 测试查询 csm_teaching_task 返回数据 |
| 建流程定义 `jygl_lecture_flow`（绑定 jygl_lecture_group） | 流程定义创建 | 绑定成功；输入参数 = 组实体数据 |

### 📅 D2：流程 2.0 五节点搭建（核心）

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 画布：开始 → 审批任务×4 → 唯一分支 → 结束 | 流程图完成 | 节点连线正确 |
| 节点① 课程负责人：审批人=**流程变量 leaderName** | 负责人节点配置 | 发起时带入 leaderName 生效 |
| 节点② 教学秘书：审批人=**流程逻辑** `findSecretaryByCollege`（输入 teachingCollege→输出 List\<String\> userName），**或签** | 教秘节点配置 | 流程逻辑输出多人时或签生效 |
| 节点③ 教务处处长：审批人=**角色**（校级角色） | 处长节点配置 | 角色成员可审批 |
| 节点④ 教学院长：审批人=流程逻辑 `findDeanByCollege`，或签 | 院长节点配置 | 同上 |
| **唯一分支**：同意→下一节点；拒绝→**回开始节点** | 驳回回路 | 拒绝后任务回到发起人 |
| 开始节点配置**审批页面**（重提页） | 开始节点审批页关联 | 驳回后发起人可见重提任务 |
| 各节点数据权限：负责人可编辑三维度字段；教务处节点**全只读** | 数据权限配置 | 教务处节点表单不可编辑；**完整字段权限表见下（jygl_lecture_group 全 22 个业务字段）** |

> 📌 **jygl_lecture_group 数据权限完整配置表（D2 实施用，2026-08-18 落定）**：
>
> | 字段 | 负责人① | 教秘②/处长③/院长④ | 开始节点(重提) |
> |------|:------:|:-----------:|:----------:|
> | title / description / version | 预览 | 预览 | **编辑** |
> | **dimProfessional / dimIdeological / dimContent** | **编辑** | 预览 | **编辑** |
> | academicYear / semester / courseCode / courseName / teachingCollege | 预览 | 预览 | 预览 |
> | leaderId / leaderName / teacherId / teacherName | 预览 | 预览 | 预览 |
> | rejectReason（驳回原因） | 预览 | 预览 | 预览 |
> | processId / taskId / auditStatus / curApprover / roundNo / itemCount / archiverName / isWithdrawn / withdrawBy / withdrawTime | 隐藏 | 隐藏 | 隐藏 |
>
> 原则：给审批人看的=预览；给负责人操作的=dim_* 编辑；给教师重提改的=title/description/dim_* 编辑；系统/流程内部字段=隐藏。
| 各节点流程权限：负责人/教秘/处长/院长=同意+拒绝；开始=提交 | 流程权限配置 | 流程按钮按节点动态渲染 |
| 🆕 **验证"任务关闭时事件"是否带审批结果**（同意/拒绝区分）——任务书 §5.4 状态回写依赖它 | 事件能力验证 | 若关闭时事件无审批结果入参 → 改用"唯一分支条件 + 自动任务"或"审批按钮 approve/reject 前后手动更新实体"方案（搭建时二选一，记录决策） |

### 📅 D3：P1 讲义总览（教师首页）

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 服务端逻辑 `loadGroupTree`（入参含 filterStatus）：教务选课号按(学期,课程)聚合 − 已有组 − isUnsubmit − is_delete=1，filterStatus 按 SQL 层+内存层分路过滤，组装嵌套 List | 逻辑完成 | 返回 `{id, courseName, courseCode, term, itemCount, version, time, groupStatus, csn, classCodeList, fileSource}` 扁平行；过滤详见 §5.1 |
| 页面拖入数据表格：树形模式 + 树型列（课程/选课号）+ 展开图标 | 树形表格 | 组行展开显示选课号子行 |
| 页面顶部筛选器区域：`filter-card` 内放 2 个筛选组件（见下方详细设计） | 筛选器 | 切换筛选后表格数据联动刷新 |
| 行操作按组状态动态：提交/重提/撤回/版本历史/审批记录/查看 | 操作列动态 | 与原型 V3 一致 |
| 组状态标签映射（6 值）+ 已通过组子行"单独修改"入口（拆组） | 状态标签 | 标签色与原型一致 |

#### D3 筛选器详细设计（2026-08-20 定稿）

**页面结构**（在数据表格上方，`.filter-card` 容器内）：

```
┌──────────────────────────────────────────────────────────────────────┐
│  任务分类 [▼ 全部任务        ]  学年学期 [▼ 2025-2026学年 第2学期]   [查询] [重置] │
└──────────────────────────────────────────────────────────────────────┘
```

---

##### 筛选器 1：任务分类（下拉选择器 · 手动添加选项）

| 配置项 | 值 |
|---|---|
| 组件 | **选择器**（PC端Vue2，70.选择器） |
| 选项来源 | **手动添加选项**（不绑定数据源，固定 6 个选项） |
| 数据类型 | 选中值为 String（平台限制，手动添加选项的"值"永远是 String） |
| 占位符 | 全部任务 |
| 样式宽度 | `width: 170px` |

**选项配置**：

| 选项文本（显示） | 选项值（值） | 对应 groupStatus |
|---|---|---|
| 全部任务 | `all` | 不过滤 |
| 待我提交 | `pending` | 6（虚拟组） |
| 审批流转中 | `processing` | 0, 1, 2, 3 |
| 被驳回待修改 | `rejected` | 5 |
| 审批已通过 | `approved` | 4 |
| 无需提交 | `nosubmit` | 含 isUnsubmit 明细的组 |

**交互逻辑**：
- `onChange` 事件 → 调用页面变量 `currentFilterStatus` 赋值为选中值
- 然后调用 `loadGroupTree` 重新查询（传入 `filterStatus = currentFilterStatus`）
- 表格数据源重新绑定后自动刷新

**注意**：任务分类和表格中"组状态"列是**两个不同口径**——任务分类是视图级筛选器（聚合所有状态），组状态是每门课审批进度的业务状态（6 值）。页面底部加一行灰色提示文字："说明：上方「任务分类」是视图筛选器；表格中的「组状态」是每门课审批进度的业务状态，两者口径不同。"

---

##### 筛选器 2：学年学期（下拉选择器 · 绑定数据源）

| 配置项 | 值 |
|---|---|
| 组件 | **选择器**（PC端Vue2，70.选择器） |
| 数据源 | 绑定服务端逻辑 `loadTermList`（见下方） |
| 文本字段 | `termLabel`（拼接显示，如"2025-2026学年 第2学期"） |
| 值字段 | `termKey`（String，格式 `"2025-2026,2"`，传给 loadGroupTree 时拆分为 academicYear + semester） |
| 默认值 | 进入页面时自动选中第一条（当前学期） |
| 样式宽度 | `width: 220px` |

**交互逻辑**：
- `onChange` 事件 → 调页面变量 `currentTerm` = 选中值
- 然后调 `loadTermSplit(currentTerm)` 得到 `currentAcademicYear` + `currentSemester`
- 调 `loadGroupTree(filterStatus, currentAcademicYear, currentSemester)` 重新查询

---

##### 学年学期数据源：`loadTermList`（服务端逻辑）

```
入参: 无（自动读取当前登录人）
出参: List<{ termLabel: String, termKey: String }>

步骤:
1. SQL 查教务数据源:
   SELECT DISTINCT
     tm.academicYear AS academicYear,
     tm.semester AS semester
   FROM CsmTeachingTeacherMap tm
   INNER JOIN CsmTeachingTask tt
     ON tm.courseSelectionNumber = tt.courseSelectionNumber
   WHERE tm.teacherCode = ${app.backend.variables.currentUser.userId}
     AND tt.isDelete = 0
   ORDER BY tm.academicYear DESC, tm.semester DESC
2. 循环 SQL 结果 → 拼装 termLabel + termKey:
   termLabel = academicYear + "学年 第" + semester + "学期"   // 显示用
   termKey   = academicYear + "," + semester                 // 传参用
3. 返回 List
```

---

##### 查询/重置按钮

| 按钮 | 样式 | 逻辑 |
|---|---|---|
| 查询 | `btn btn-primary btn-sm` | 触发 `loadGroupTree(filterStatus, academicYear, semester)` |
| 重置 | `btn btn-plain btn-sm` | 将两个筛选器恢复默认值（任务分类=all，学年学期=当前学期），然后触发 loadGroupTree |

---

##### 各 filterStatus 值对应的 loadGroupTree 行为

| filterStatus | groupList SQL | itemList SQL | 虚拟组（groupStatus=6） | 组行过滤 |
|---|---|---|---|---|
| `all` | 全量 | 全量 | ✅ 装 | 全装 |
| `pending` | 全量 | 全量 | ✅ 装 | 全装（前端按 groupStatus=6 显示） |
| `processing` | auditStatus IN (0,1,2,3) | 全量 | ❌ 跳过 | 全装 |
| `rejected` | auditStatus = 5 | 全量 | ❌ 跳过 | 全装 |
| `approved` | auditStatus = 4 | 全量 | ❌ 跳过 | 全装 |
| `nosubmit` | 全量 | isUnsubmit = 1 | ❌ 跳过 | 只装含 unsubmit 明细的组 |

### 📅 D4：P2 提交申请页（课程组维度）

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 页面：课程组信息（5 字段一行，只读）+ 选课号明细（树形多选，默认全选，父子双向关联）+ 讲义信息（标题*/描述）+ 共享文件区 + 按钮行（返回左/提交右） | 页面布局 | 与原型 V3 一致 |
| 数据表格多选列：**关联选中类型=父子双向关联选中**，进入时初始化全选 | 多选交互 | 勾选课程=全选子级；反选子级=取消父级 |
| 课程共享文件上传组件（多文件）+ 明细行内"单独上传"（每行一个上传组件，只读展示共享/专属状态） | 两级上传 | 共享对全部选中生效；专属仅该行；解析规则=专属优先否则共享 |
| 服务端逻辑 `doSubmit`（见 §5.2） | 提交逻辑 | 校验标题+至少1文件+至少1选中 → 写组/明细/文件 → launchProcess → 回写 processId + auditStatus=0 |
| 重提场景：驳回原因提示条 + 预填旧内容 + 版本 v(N+1) | 重提预填 | 与原型一致 |
| 提交成功弹窗 → 回讲义总览 | 完成反馈 | 流程已发起 |

### 📅 D5：P4 审批页（五节点动态）

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 审批页：流程表单（组信息+选课号明细只读表+文件预览）+ 流程信息 + 流程记录 + 流程图 + 流程按钮 | 页面组件 | 全部基于 taskId 正常渲染 |
| 选课号明细只读表：数据源=按 groupId 查 jygl_lecture_group_item（普通表格，非树形） | 明细表 | 含文件来源列（共享/专属） |
| 三维度审核表单（专业/思政/内容 通过·不通过）——仅负责人节点可编辑 | 数据权限 | 其他节点只读或隐藏 |
| 审批意见（驳回必填）——流程按钮拒绝前校验 | 校验逻辑 | 拒绝无意见时拦截 |
| 审批记录/评论分段：流程记录组件 + 流程评论（平台组件，不建表） | 记录+评论 | 评论随流程实例存储 |
| 教务处节点：全只读 banner + 表单不可编辑 | 只读呈现 | 与原型 readonly-banner 一致 |

### 📅 D6：审批待办列表 + P5 学院提交情况页

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 审批待办列表：分段 Tab（待审批/已处理/全部）+ 表格（讲义标题/课程/提交人/学院/教学班数/时间/当前节点/状态/操作[审批/审批记录]） | 列表页 | 数据源=getMyPendingTasks/getMyCompletedTasks + 组表补充字段 |
| 待办过滤：负责人=leaderId；教秘/院长=teachingCollege=本学院；处长=全校 | 权限过滤 | 各角色所见正确 |
| 🆕 **先实现 `resolveUserRole`（§5.8）再配待办过滤**：列表数据源统一走"角色判定→拼过滤条件"，同一张表格多角色复用（不建权限表） | 角色判定逻辑 | 教师/负责人/教秘/院长/处长切换登录所见范围正确（⚠️ 依赖 P0 B-04 学院→教秘/院长映射） |
| 任务箱组件放顶栏（红点提醒+跳转） | 任务箱 | 待办数实时 |
| P5 学院提交情况：开课学院锁定下拉 + 学年学期 + 4 统计卡（已通过/流程中/未提交/无需提交）+ 课程组表格 | 页面 | 统计口径=课程组 |
| 学院详情：5 Tab（全部/已通过/流程中/未提交/无需提交）+ 选课号明细表（含归档人列） | 详情页 | 归档人=archiverName |
| 无需提交/撤销：明细行按钮 + 二次确认弹窗 + 服务端逻辑 `markUnsubmit`/`cancelUnsubmit` | 功能 | isUnsubmit 落库；教师端任务消失/恢复 |

### 📅 D7：P6 教务总览 + P3 提交历史

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 服务端逻辑 `loadOverviewStat`：按学院聚合 应提交/已通过/流程中/未提交/提交率 + 各环节积压（4 节点各待审数） | 统计逻辑 | 口径与 P5 一致 |
| P6 页面：学年+学期筛选（统计卡上方）+ 4 统计卡 + 积压卡 + 学院表格（查看明细只读） | 页面 | 筛选切换刷新统计 |
| P3 提交历史：组维度历史（轮次/状态/驳回原因/当前审批人） | 页面 | 数据源=组表 roundNo 记录 |

### 📅 D8：P7 流转记录 + 撤回/重提/版本 + 状态回写

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| P7 流程流转记录页：流程图 + 流程记录组件（组级流程实例时间线） | 页面 | 五节点时间线完整 |
| 撤回逻辑：流程按钮撤回（withdrawTask）→ 组表 isWithdrawn=1，回待提交，不增轮次 | 撤回 | ⚠️ **平台限制（2026-08-18 文档核对）**：撤回仅限"提交后→开始节点下一节点（课程负责人）未处理前"；负责人已处理（哪怕卡在教秘/处长/院长）则 withdrawTask 不可用，只能走驳回或走完流程。重提后 isWithdrawn 清零 |
| 重提逻辑：开始节点 submitTask（原流程实例继续，process_id 不变）→ roundNo+1 | 重提 | 版本 v+1；⚠️ 驳回/撤回后重提均用 **submitTask**，不要重新 launchProcess（会新建流程实例，与"process_id 不变"矛盾，导致同组双实例） |
| **流程事件回写**（关键）：各审批节点"任务创建时事件"用 curr.nodeParticipants 更新 curApprover/curNode；"任务关闭时事件"更新 auditStatus/itemStatus；**结束节点前自动任务**：终节点通过人写入 archiverName，组+全部明细置为通过(4) | 回写逻辑 | 与"流程数据与实体数据的同步.md"模式一致 |
| 版本历史：`getFileVersionListByFileId`（鸿翼 V1.5）预留；MVP 用文件表 roundNo 展示 | 版本展示 | MVP 本地版本列表 |

### 📅 D9：拆组机制 + 全流程联调

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 服务端逻辑 `splitGroup`：已通过组内选课号"单独修改"→ 新建组（拷贝组字段，仅含该选课号，roundNo+1，文件预填）→ 明细写 splitGroupId → 新组独立 launchProcess | 拆组逻辑 | 原组不受影响；拆组留痕可查 |
| 全流程联调（按 §六 验收清单逐项走） | 联调通过 | 场景 1~8 全部走通 |
| 数据权限复查：教师/负责人/学院/全校四级过滤 | 权限复查 | 与 V1.5 四级权限一致 |

### 📅 D10：验收 + 发布 + 收尾

| 任务 | 交付物 | 验收标准 |
|------|--------|---------|
| 回归测试（角色切换 × 全状态流转 × 边界：驳回必填意见、无文件拦截、撤回答限制） | 测试报告 | 无 P0/P1 缺陷 |
| 发布开发环境 → 用户验收环境 | 发布 | 演示数据齐全 |
| 文档收尾：页面-逻辑-实体映射表更新；积压项清单核对 | 文档 | 与搭建指南一致 |

---

## 五、关键逻辑详细编写（NASL 伪代码）

### 5.1 `loadGroupTree`（P1 树形数据源，服务端逻辑）

```
入参: filterStatus: String, academicYear: String, semester: Integer
出参: List<Map>（扁平行，parentId 区分父子）

filterStatus 可选值: all / pending / processing / rejected / approved / nosubmit
groupStatus 含义: 0-3=审批流转中, 4=已通过, 5=已驳回, 6=虚拟待提交组（无组记录）

步骤:
1. 查教务选课号:
   SELECT ... FROM CsmTeachingTask t LEFT JOIN TpmCourseTable c
   WHERE t.isDelete=0 AND c.isDelete=0 AND academicYear/semester 匹配
     AND teacherIdGroup LIKE '%当前用户%'   （教务数据源）
     → 结果: teachingTasks（csn/courseName/courseCode/classCodeList）

2. 查已有组（filterStatus 分 4 路 SQL）:
   - all / pending / nosubmit → 全量组
   - processing → auditStatus IN (0,1,2,3)
   - rejected → auditStatus = 5
   - approved → auditStatus = 4
   （应用库数据源）
     → 结果: groupList

3. 查明细（filterStatus 分 2 路 SQL）:
   - nosubmit → 只查 isUnsubmit=1 的明细
   - 其余 → 全量明细
   （应用库数据源）
     → 结果: itemList

4. 循环 itemList → 收集:
   submittedCsnList  = 已提交的选课号（去重）
   unsubmitCsnList   = 无需提交的选课号（isUnsubmit=true）

5. 循环 groupList → 组装组行（parent, parentId=null）:
   - nosubmit 时只装含 unsubmitCsnList 中选课号的组（hasUnsubmit 判断）
   - 其余全量装

6. 循环 itemList → 组装明细行（child, parentId="g"+groupId）

7. 循环 teachingTasks → 组装虚拟待提交组（groupStatus=6）:
   - 仅 filterStatus=all 或 pending 时才执行（其余跳过）
   - 排除 submittedCsnList 和 unsubmitCsnList 中的选课号
   - 按 courseCode 去重（addedCourseMap），每个课程一个父行 + N 个子行

8. 返回 result（扁平行列表，前端数据表格·树形模式按 parentId 渲染）
```

> **筛选器配置详见 D3 表格行内「D3 筛选器详细设计」小节**；页面顶部 2 个下拉框：
> - 任务分类 → 手动添加选项（String 值），onChange 传 filterStatus
> - 学年学期 → 绑定 `loadTermList`（SQL 查教务去重），onChange 拆分 academicYear + semester
> - 查询按钮 → 触发 loadGroupTree；重置按钮 → 恢复默认值再触发

### 5.2 `doSubmit`（P2 提交，服务端逻辑）

```
入参: groupData(组字段), selectedItems(List<选课号>), sharedFiles(List<fileName>), itemFiles(Map<选课号, List<fileName>>), 是否重提
步骤0（查课程负责人 leaderName，2026-08-18 补）:
   a. 查教务: tpm_approval_set WHERE course_code = 当前课程（course_code 主键 1:1）
      → leaderId = task_user3（负责人工号）
   b. 查教务: sys_teacher_info WHERE employee_id = leaderId
      → leaderName = leaderId + ":" + employee_name   // 格式"工号:姓名"，必须与 LCAPUser.userName 一致
   c. 验证 SQL（Navicat 跑，确认真实格式）:
      SELECT a.course_code, a.task_user3, t.employee_name,
             CONCAT(a.task_user3, ':', t.employee_name) AS leader_name_final
      FROM tpm_approval_set a LEFT JOIN sys_teacher_info t ON a.task_user3 = t.employee_id
      WHERE a.course_code = 'J9041002' LIMIT 5;
步骤:
1. 校验: 讲义标题非空；selectedItems 非空；每个选中选课号至少一份有效文件
   (专属优先，否则必须存在共享文件)
2. 事务:
   a. 写 jygl_lecture_group（auditStatus=0, roundNo=原+1 或 1, version="v"+roundNo,
      leaderId=步骤0的leaderId, leaderName=步骤0的leaderName）
   b. 逐条写 jygl_lecture_group_item（每个选中选课号一行, itemStatus 跟随组）
   c. 写 jygl_material_file:
      - 共享文件: itemId=null（group 级）
      - 专属文件: itemId=对应明细 id
3. 调流程: launchProcess(flowKey='jygl_lecture_flow', data=group)
   ⚠️ 注意: CodeWave 流程 2.0 的 launchProcess **没有 variables 参数**——"流程变量"= 流程绑定实体的属性字段，
   leaderName 已作为实体属性随 data 带入流程，节点①审批人方式选"流程变量 leaderName"即读取该字段
   → 返回 processId
4. 回写: group.processId = processId
5. 返回 { success, processId, groupId }
```

### 5.2.1 `doSubmit` 前置验证——怎么发起流程（D2 阶段，2026-08-18 补）

> D2 只搭流程、页面 D4/D5 才做。验证流程能否跑通，需要**临时手段发起一个测试流程**，不用等 D4 提交页：

**方式一（推荐）：一键生成申请页临时发起**
```
① 选中流程 jygl_lecture_flow → 属性 → "一键生成申请页面"（createJyglLectureGroup）
   → 生成发起页（含服务端逻辑），教师填表 → 提交即 launchProcess
② 用 leaderName 测试值验证：
   测试发起时临时在页面/逻辑里写死 leaderName = "工号:姓名"（如 20191012:张明）
   → 负责人节点待办应出现该用户的待办
③ 验证通过后：该申请页后续改造为 P2 提交页（D4），临时写死值替换为步骤0查库逻辑
```

**方式二：直接调 launchProcess 逻辑测试**
```
① 在服务端逻辑里写一个临时测试逻辑 launchTestProcess：
   构造一个 jygl_lecture_group 实体，直接给 leaderName 属性赋值（写死测试值 "20221073:张蓓蓓"）
   data = 该实体（leaderName 作为实体属性随 data 带入流程）
   flowKey = jygl_lecture_flow
   ⚠️ launchProcess 无 variables 参数，流程变量=实体属性，勿再写 variables
② 页面放个按钮调用它（或逻辑调试直接跑）
③ 验证：负责人工号登录 → 任务箱出现待办 → 打开审批页 → 走同意/拒绝
```

**D2 验收对照**：验收项 1~8 都用上述方式发起测试流程逐项验证；通过后进入 D3/D4 再做正式页面。

### 5.3 审批人动态查人（流程逻辑，节点②④审批人）

```
逻辑名: findApproversByCollege
入参: teachingCollege(String)
出参: List<String> (userName 列表, 格式"工号:姓名")

实现(以教秘为例):
1. 查 sys_department_information: department_name/type 匹配"教学秘书"岗位或职务映射
   (若教务有岗位/职务表则按岗位查；否则维护"学院→教秘工号"映射表)
2. 查 sys_teacher_info: 该学院 + 职务=教学秘书
3. 组装 userName 列表返回（多人逗号拼接 → 流程节点配"或签"）
```

> ⚠️ 实现提示：教务若已导入"职务"体系可查职务表；否则在 CodeWave 建一张轻量映射（学院+职务→工号列表，V1.5 鸿翼职位体系可替换）。

### 5.4 状态回写（流程事件 + 自动任务）

```
【各审批节点 · 任务创建时事件】
  jygl_lecture_group.curApprover = curr.nodeParticipants
  jygl_lecture_group.curNode      = curr.nodeTitle

【各审批节点 · 任务关闭时事件】
  同意: auditStatus = 下一节点值(0→1→2→3)；明细 itemStatus 同步
  拒绝: auditStatus = 5(已驳回)；rejectReason = 审批意见；明细 itemStatus 回开始

【结束节点前 · 自动任务节点】
  data(流程数据) → 更新实体:
  jygl_lecture_group.auditStatus = 4(已通过)
  jygl_lecture_group.archiverName = 终节点通过人(userName)
  全部明细 itemStatus = 4
```

### 5.5 `markUnsubmit` / `cancelUnsubmit`（P5，明细级）

```
入参: itemId
markUnsubmit: 校验(教师未提交该选课号) → item.isUnsubmit=1 → 记录操作人/时间
cancelUnsubmit: item.isUnsubmit=0
```

### 5.6 `splitGroup`（拆组，已通过组）

```
入参: groupId, itemId
步骤:
1. 校验: 组 auditStatus=4(已通过) 且明细 splitGroupId 为空
2. 新建 jygl_lecture_group:
   拷贝原组 courseCode/Name/College/leaderId/teacherId/title/description
   roundNo = 原组 roundNo+1；仅含该 1 个选课号；文件预填原组共享文件
3. 原明细 splitGroupId = 新组 id
4. 新组 launchProcess（独立走五节点）
```

### 5.7 `resolveUserRole`（登录人角色判定，表格复用前置）🆕

> 背景：P1/P4/P5/P6 多处**同一张数据表格多角色复用**，靠"按登录人角色动态拼过滤条件"实现行级数据隔离（不建冗余权限表）。本逻辑是第一步——先判登录人是哪个角色，调用方再选过滤条件。
>
> 🆕 **2026-08-18 重大简化**：`CodeWave currentRole` 全局变量已含业务角色体系（businessRoleId / businessRoleName / businessOrgs / orgId / isAdmin），教秘/院长/处长的判定**不再依赖自建轻量映射表**（积压项 P0 B-04 由此关闭）。

```
入参: userId(登录人工号 currentUser.userId) + currentRole(全局变量，含业务角色)
出参: { roles: List<String>, primaryRole: String, collegeId: String? }
       roles 取值: TEACHER(教师) / LEADER(课程负责人) / SECRETARY(教秘) / DEAN(教学院长) / DIRECTOR(教务处处长) / ADMIN(校领导)

判定顺序（命中即记录，全部查完再定 primaryRole）:
1. 教师 (TEACHER):
   - 主信号: currentRole.businessRoleName == "jygl_teacher"
   - 副信号(冗余校验): 查教务 csm_teaching_teacher_map WHERE teacher_code = userId AND is_delete = 0（确认是否真有授课任务）
2. 课程负责人 (LEADER):
   - 主信号: currentRole.businessRoleName == "jygl_course_leader"
   - 副信号(冗余校验): 查教务 tpm_approval_set WHERE task_user3 = userId AND is_delete = 0
3. 教秘/教学院长 (SECRETARY / DEAN):
   - 主信号: currentRole.businessRoleName == "jygl_secretary" / "jygl_dean"
   - collegeId = currentRole.businessOrgs[0]（该角色对应的部门 id，天然给出开课学院）
   - 无需查教务、无需自建映射表（B-04 关闭）
4. 教务处处长 (DIRECTOR) / 校领导 (ADMIN):
   - 处长: currentRole.businessRoleName == "jygl_director"
   - 校领导: currentRole.businessRoleName == "校领导" / isAdmin == true
   - 无需 collegeId（全校无过滤）

primaryRole 优先级（角色重叠时，如教师兼课程负责人）:
   DIRECTOR > DEAN > SECRETARY > LEADER > TEACHER > ADMIN
   （说明: 处长/院长/教秘审批角色优先于教师/负责人，保证进入审批视角；
     仅 ADMIN 单独判定——若用户同时是校领导与教师，以 ADMIN 为准进总览）

应用示例:
- P1 讲义总览: primaryRole 含 TEACHER/LEADER 才显示（教师=自己的组；负责人=所负责课程的组）
- P4 审批待办: 过滤条件 = primaryRole → leaderId(LEADER) / teachingCollege(SECRETARY|DEAN, 取 currentRole.businessOrgs[0]) / 无过滤(DIRECTOR)
- P5 学院提交情况: SECRETARY/DEAN 可见，collegeId = currentRole.businessOrgs[0]
- P6 教务总览: DIRECTOR/ADMIN 可见，全校无过滤

⚠️ 依赖 D0-6 业务角色配置（先在 CodeWave 业务角色管理里建 5 个角色 + 指派人员）
⚠️ 角色重叠场景：currentRole.businessRoleName 是单值，若教师兼负责人需在业务角色里给一个 primary（按优先级选）；登录后用 currentRole 直接得主要视角，其他角色可在前端做"切换身份"
```

### 5.8 `loadOverviewStat`（P6 教务总览）

```
入参: academicYear, semester
出参: { totalGroups, approved, processing, unsubmitted, unsubmit,
        byCollege: List<{college, total, approved, processing, unsubmitted, rate}>,
        backlog: {node0..node3 各待审数} }
实现:
- 应提交组 = loadGroupTree 全校聚合（排除 isUnsubmit 明细、软删选课号）
- 已通过 = auditStatus=4；流程中 = 0~3；未提交 = 应提交 − 已提交组
- 各环节积压 = COUNT(auditStatus=0/1/2/3)
```

---

## 六、全流程验收清单（D9/D10 逐项走）

| # | 场景 | 操作 | 预期 |
|---|------|------|------|
| 1 | 提交 | 教师选课 → 提交（默认全选+共享文件） | 组表/明细/文件落库；流程到负责人；总览出现"待课程负责人审核" |
| 2 | 负责人通过 | 三维度全过 → 同意 | 状态 0→1；明细同步 |
| 3 | 负责人驳回 | 某维度不通过 → 拒绝(必填意见) | 整组回开始节点；教师总览"已驳回"+驳回原因 |
| 4 | 重提 | 教师修改后重提 | roundNo+1、版本 v+1、重新到负责人 |
| 5 | 教秘/处长/院长 | 依次通过（处长节点只读） | 状态 1→2→3→4；archiverName=院长 |
| 6 | 撤回 | 流程中撤回 | isWithdrawn=1；回待提交；重提后清零 |
| 7 | 无需提交 | 教秘标记某选课号 | 教师端该选课号消失；撤销后恢复 |
| 8 | 拆组 | 已通过组某选课号"单独修改" | 新组独立流程；原组不受影响 |
| 9 | 权限 | 四级角色查看 | 教师=自己；负责人=负责课程全部教师；学院=本学院；处长=全校 |

---

## 七、参考文档（CodeWave 官方文档）

- `20.应用开发/20.流程设计/20.流程2.0/30.流程设计及使用.md` — 流程与实体绑定、业务数据带入
- `20.应用开发/20.流程设计/20.流程2.0/40.流程节点配置说明.md` — 节点类型、审批人 6 种方式、开始节点配审批页面
- `20.应用开发/20.流程设计/20.流程2.0/50.流程组件.md` — 任务箱/我的流程/流程按钮/流程信息/流程记录/流程图/流程表单
- `20.应用开发/20.流程设计/20.流程2.0/60.流程数据与实体数据的同步.md` — 自动任务/流程事件回写（curr.nodeParticipants/curr.nodeTitle/data）
- `20.应用开发/20.流程设计/20.流程2.0/70.流程逻辑使用说明.md` — launchProcess/approveTask/rejectTask/submitTask/withdrawTask/revertTask/getMyPendingTasks（lcap process framework v1.10.0）
- `20.应用开发/20.流程设计/20.流程2.0/90.流程使用常见问题.md` — 或签/会签/依次审批；流程变量/流程逻辑动态指定审批人；userName 注意事项
- `20.应用开发/10.页面设计/20.PC端Vue2组件说明（默认）/50.表格/100.数据表格.md` — 树形模式、多选列、父子双向关联选中
- `20.应用开发/10.页面设计/20.PC端Vue2组件说明（默认）/60.表单/158.文件上传.md` — 值=String、多文件、只读、列表类型
- `80.常见场景案例/40.组件场景/40.其他组件场景/020.如何使用上传组件上传图片和文件.md` — 数据表格列内嵌上传组件
- `80.常见场景案例/40.组件场景/20.表格场景/095.如何使用数据表格展示树形结构.md` — 树形嵌套 List
- `80.常见场景案例/40.组件场景/20.表格场景/122.如何实现数据表格的单选和多选.md` — 多选列+多选值

---

**文档结束**
