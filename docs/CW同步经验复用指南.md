# CW 同步经验复用指南

> 来源项目：特色班报名系统（RegistrationQuestionnaire）
> 目标项目：授课讲义管理系统（LectureManagementSystem）
> 生成日期：2026-08-13
> 用途：将报名系统内外网同步的踩坑经验，提炼为讲义系统可复用的避坑指南 + 同步设计建议

---

## 一、项目背景与同步场景对比

### 报名系统（经验来源）

- **架构**：外网 Java 后端 ↔ 内网 CW 低代码平台，**双向同步**
- **外网→内网**：GET 接口拉取（CW 主动拉外网数据）
- **内网→外网**：POST 接口推送（管理员操作后同步回外网）
- **同步内容**：categories / classes / classRounds / classCategory / applications / notice
- **认证**：外网 API 需 Bearer token 登录

### 讲义系统（目标项目）

- **架构**：教务系统 MySQL → CW 低代码平台，**单向拉取**
- **同步方向**：教务库 → CW（手动 + 定时 cron）
- **同步内容**：教务 10 张表（学年/部门/教师/教学任务/课程/课程负责人等）
- **数据源**：CW 数据源直连教务库（不用 API/导出）
- **关键区别**：教务数据对 CW 是**只读**，CW 不往教务写任何东西

### 核心差异影响

| 差异点 | 报名系统 | 讲义系统 | 对复用的影响 |
|--------|---------|---------|------------|
| 同步方向 | 双向 | 单向 | 不需要"内网→外网 POST"相关经验 |
| 数据源 | REST API | 数据库直连 | 不需要 token 认证相关经验 |
| 写入权限 | 双方都可写 | 教务只读 | 终态保护逻辑（status=3/4 不覆盖）不适用 |
| 冲突处理 | 内外网 id 独立需 outerId | 无冲突 | outerId 方案不需要 |

**结论**：同步策略、NASL 踩坑、时区处理、SQL 踩坑、Java 扩展等经验**高度可复用**；双向同步特有经验（终态保护、outerId、POST 回推）**不适用**。

---

## 二、同步策略选择

### 三种策略对比

| 策略 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| **全量覆盖**（truncate 再插） | 数据量可控、源数据权威 | 逻辑简单、无边界 bug | 临时清空有短暂不可用窗口 |
| **差量比对**（逐条比较增删改） | 数据量大、需保留本地修改 | 不丢数据、增量同步 | 边界情况多（日期格式/字段遗漏/匹配逻辑） |
| **按条件同步**（只同步特定状态） | 部分数据有业务约束 | 保护终态数据 | 只适用于特定场景 |

### 报名系统的教训

报名系统最初用**差量比对**同步 categories/classes，踩了 30+ 个坑（日期格式不兼容、新建班级丢关联、计数永远少 1 等），最终改为**全量覆盖**，代码从 ~450 行降到 ~80 行。

**关键结论**：
- **差量比对是坑王**，除非有明确的业务约束（如 applications 不能全量覆盖会丢录取状态），否则优先全量覆盖
- 全量覆盖的 FK 约束问题：MySQL TRUNCATE 被外键约束阻挡，需 `SET FOREIGN_KEY_CHECKS=0` + `TRUNCATE` + `SET FOREIGN_KEY_CHECKS=1`
- 全量覆盖的顺序：被依赖的表先清再插（如 categories 必须先于 classes）

### 讲义系统同步策略建议

教务数据对 CW 是**只读拉取**，不存在"CW 修改后不能被覆盖"的问题，因此：

| 教务表 | 建议策略 | 理由 |
|--------|---------|------|
| `sys_academic_year` | 全量覆盖 | 数据量小（几十行），学年学期字典表 |
| `sys_department_information` | 全量覆盖 | 部门树，数据量小 |
| `sys_teacher_info` | 全量覆盖 | 教师表，几千行，CW 不修改 |
| `tpm_course_table` | 全量覆盖 | 课程字典表 |
| `tpm_approval_set` | 全量覆盖 | 课程负责人映射，CW 不修改 |
| `csm_teaching_task` | 全量覆盖（带过滤） | 教学任务，2.4 万行，需过滤 `is_delete=1` 和 `stop_type` |
| `csm_teaching_teacher_map` | 全量覆盖（带过滤） | 跟随教学任务过滤 |
| `csm_teaching_class_map` | 全量覆盖（带过滤） | 同上 |
| `tpm_course_replace_code` | 全量覆盖 | 课程替换映射 |

**过滤条件建议**：
- `csm_teaching_task`：`WHERE is_delete = 0`（排除已删除），可选 `AND stop_type IS NULL`（排除停开课）
- 关联表跟随主表过滤：只同步 `course_selection_number` 在过滤后教学任务中存在的记录

**同步顺序**（被依赖的先同步）：
```
① sys_academic_year（无依赖）
② sys_department_information（无依赖）
③ sys_teacher_info（依赖 department）
④ tpm_course_table（依赖 department）
⑤ tpm_approval_set（依赖 course + teacher）
⑥ csm_teaching_task（依赖 course + teacher + academic_year）
⑦ csm_teaching_teacher_map（依赖 teaching_task + teacher）
⑧ csm_teaching_class_map（依赖 teaching_task）
⑨ tpm_course_replace_code（依赖 course）
```

---

## 三、CW NASL 通用踩坑速查

> 以下每条都是报名系统实际踩过的坑，按"高频/致命"排序。写 NASL 代码时逐条检查。

### 3.1 List/Map 声明必须初始化

```nasl
// ❌ 错误：只是类型声明，不是初始化
let catIds: List<Integer>       // Add 时报错或 undefined

// ✅ 正确：声明 + 初始化
let catIds: List<Integer> = []: List<Integer>
```

**检查清单**：所有 `let xxx: List<T>` 和 `let xxx: Map<K,V>` 后面必须有 `= []` 或 `= {}`。

### 3.2 全局变量在循环内残留

```nasl
// ❌ 错误：循环外初始化的 List，每轮 Add 累积上轮值
let allItems: List<String> = []: List<String>
for (item in sourceList) {
    // allItems 没有每轮清空，数据越攒越多
    Add(allItems, item.name)
}

// ✅ 正确：每轮开始时清空
for (item in sourceList) {
    allItems = []: List<String>   // 每轮重置
    Add(allItems, item.name)
}
```

### 3.3 Add 位置错误

```nasl
// ❌ 错误：Add 在内层循环里，每匹配一次就 Add 一次
for (innerCls in innerClasses) {
    for (r in innerRounds where r.classId == innerCls.id) {
        Add(classRoundsForApi, {...})   // 重复添加
    }
    Add(clsData, { classRounds: classRoundsForApi })
}

// ✅ 正确：Add 在内层循环外部，只执行一次
for (innerCls in innerClasses) {
    classRoundsForApi = []: List<ClassRound>
    for (r in clsRounds) {
        Add(classRoundsForApi, {...})
    }
    Add(clsData, { classRounds: classRoundsForApi })  // ✅ 在外层
}
```

### 3.4 MapContains vs == null

```nasl
// ❌ 错误：MapGet 返回 undefined，不是 null
if (matched == null && ...)    // 永远不成立

// ✅ 正确：用 MapContains 判断 key 是否存在
if (MapContains(innerClassByName, trimmedOuterName) == false && ...)
```

### 3.5 嵌套循环 index 命名

```nasl
// ❌ 错误：两层循环都用 index2，内层 shadow 外层
for (innerRound in innerRoundsList, index2) {
    for (outerRound in outerCls.classRounds, index2) {  // ❌ 重复
    }
}

// ✅ 正确：各层用不同 index
for (innerRound in innerRoundsList, index2) {
    for (outerRound in outerCls.classRounds, index3) {  // ✅ index3
    }
}
```

### 3.6 else 分支必须重置变量

```nasl
// ❌ 错误：else 分支没重置 needUpdate，可能读到上一轮的值
if (found == true) {
    needUpdate = true
} else {
    // needUpdate 没重置，可能是上一轮的 true
    if (...) { ... }
}

// ✅ 正确：else 分支开头重置
else {
    needUpdate = false   // ✅ 先重置
    if (...) { ... }
}
```

### 3.7 Entity{} 字面量是重新创建，不是修改

```nasl
// ❌ 错误：if/else 里改了属性，但 Entity{} 重新创建会覆盖
if (MapContains(commentMap, outerApp.id)) {
    newApp.auditComment = MapGet(commentMap, outerApp.id)  // 改了
} else {
    newApp.auditComment = outerApp.auditComment
}
newApp = app::dataSources::defaultDS::entities::SscApplications {
    auditComment=outerApp.auditComment,  // ← 覆盖了 if/else 的赋值！
}

// ✅ 正确：用局部变量中转
if (MapContains(commentMap, outerApp.id)) {
    auditComment = MapGet(commentMap, outerApp.id)
} else {
    auditComment = outerApp.auditComment
}
newApp = app::dataSources::defaultDS::entities::SscApplications {
    auditComment=auditComment,  // ✅ 用局部变量
}
```

### 3.8 update vs updateBy 区别

```nasl
// update：单条更新，无 projection
SscClassesEntity::update(entity)   // ✅ 直接传实体

// updateBy：批量更新，有 filter + projection
SscApplicationsEntity::updateBy(
    filter = SscApplications.isDeleted == 1,   // ✅ 用平台自动生成变量
    projection = { item: SscApplications => [
        SscApplications.status = 4
    ]}
)
```

**注意**：`update` 只有一个 body 参数，不需要 projection。projection 是 `updateBy` 的语法。

### 3.9 deleteBy filter 语法

```nasl
// ❌ 错误：用了循环变量 a
SscApplicationsEntity::deleteBy(filter = a.isDeleted == 1)

// ✅ 正确：用平台自动生成的同实体名变量
SscApplicationsEntity::deleteBy(filter = SscApplications.isDeleted == 1 && HasValue(SscApplications.outerId))
```

**规则**：Entity::updateBy / deleteBy 的 filter 是独立作用域，变量名由平台自动生成（= 实体名），与外层循环变量无关。

### 3.10 NASL 不支持 ?? 空值合并运算符

```nasl
// ❌ 错误：JS 语法，NASL 不支持
let comment = a.auditComment ?? ''

// ✅ 正确：用 HasValue + if 判断
if (HasValue(a.auditComment)) {
    thisAuditComment = a.auditComment
} else {
    thisAuditComment = ''
}
```

### 3.11 DateTime 类型转 String 需显式 Convert

```nasl
// ❌ 错误：实体字段 DateTime，API 需要 String，直接传类型不匹配
periodStart: r.periodStart

// ✅ 正确：显式转换
periodStart: Convert<String>(r.periodStart)
```

**注意**：如果实体字段已改为 String 类型，则不需要 Convert。

### 3.12 循环变量作用域——内层循环后变量残留

```nasl
// ❌ 错误：内层循环修改变量后，外层判断依赖该变量，值已被覆盖
for (innerAssoc in innerClassCatList) {
    for (catName in outerCls.categories) {
        categoryId = getCategoryIdByName(catName)  // 每次覆盖
    }
    if (outerCatMatch == false) {
        // categoryId 是最后一个 catName 的值，不是当前 innerAssoc 的
    }
}

// ✅ 正确：用独立变量保存当前需要比较的值
for (innerAssoc in innerClassCatList) {
    let thisCatId = innerAssoc.categoryId   // ✅ 保存到独立变量
    for (catName in outerCls.categories) {
        categoryId = getCategoryIdByName(catName)
        if (thisCatId == categoryId) { outerCatMatch = true; break }
    }
}
```

### 3.13 name 匹配用 Map + Trim 防空格

```nasl
// ❌ 错误：嵌套循环 + 每次比较，效率低且空格导致漏匹配
for (outerCls in outerClasses) {
    for (innerCls in innerClasses) {
        if (outerCls.name == innerCls.name) { ... }  // 多空格就匹配不上
    }
}

// ✅ 正确：Map 优化 + Trim 去空格
let innerClassByName: Map<String, SscClasses> = {}: Map<String, SscClasses>
for (innerCls in innerClasses) {
    let trimmedName = Trim(innerCls.name)
    MapPut(innerClassByName, trimmedName, innerCls)
}
for (outerCls in outerClasses.data) {
    let trimmedOuterName = Trim(outerCls.name)
    if (MapContains(innerClassByName, trimmedOuterName) == false && ...) {
        // 处理
    }
}
```

### 3.14 大列表 POST 分批处理

```nasl
// ❌ 错误：上千条 id 一次 POST，可能超时
POST /api/admin/applications/admit  Body: { ids: admitIds }  // 1000条

// ✅ 正确：分批，每批最多 100 条
let batchSize = 100
let i = 0
while (i < Length(admitIds)) {
    let batchIds = Slice(admitIds, i, i + batchSize)
    POST /api/admin/applications/admit
    Body: { ids: batchIds }
    i = i + batchSize
}
```

### 3.15 CW bundler 嵌套 for + if 条件判断组合有解析 bug

**现象**：CW bundler 报 `Unexpected token '*'`，但代码语法看起来没问题。

**根因**：嵌套 for 循环 + if 条件判断组合触发了 CW bundler 的解析 bug，不是某个语法元素的问题。

**绕过方案**：去掉 if 判断，让逻辑直接执行（空列表遍历不会执行，等价于跳过）。

---

## 四、CW 时区与日期处理

### 4.1 DateTime picker UTC 偏移 +8h

**问题**：CW 日期时间选择器传出 UTC 格式 `2026-07-08T00:00:00.000Z`，用户输入 08:00 实际传出 00:00（UTC），存入数据库变成 00:00 而不是 08:00。

**根因**：CW DateTime picker 在传出时自动将本地时间转换为 UTC（减 8 小时）。

**影响**：所有通过 DateTime picker 输入的时间字段都会偏移 -8h。

**解法**：Java 扩展逻辑 `convertUtcToLocal`，把 UTC 字符串加 8 小时转回本地时间：

```java
@Service
public class ConvertUtcToLocal {
    public String convertUtcToLocal(String utcString) {
        if (utcString == null || utcString.length() < 20) {
            return utcString;
        }
        String datePart = utcString.substring(0, 10);
        int hour = Integer.parseInt(utcString.substring(11, 13));
        String minute = utcString.substring(14, 16);
        String second = utcString.substring(17, 19);
        int correctHour = (hour + 8) % 24;
        if (hour >= 16) {
            // 日期+1（纯字符串处理，不用 LocalDate）
            String[] parts = datePart.split("-");
            int year = Integer.parseInt(parts[0]);
            int month = Integer.parseInt(parts[1]);
            int day = Integer.parseInt(parts[2]);
            day++;
            if (day > 31) { day = 1; month++; if (month > 12) { month = 1; year++; } }
            datePart = "" + year + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day;
        }
        String finalHour = correctHour < 10 ? "0" + correctHour : "" + correctHour;
        return datePart + " " + finalHour + ":" + minute + ":" + second;
    }
}
```

**NASL 调用**：
```nasl
fmtStart = app::logics::ConvertUtcToLocal::convertUtcToLocal(item.periodStart)
fmtEnd = app::logics::ConvertUtcToLocal::convertUtcToLocal(item.periodEnd)
```

**讲义系统适用性**：讲义系统有时间输入（学年学期、审批时间等），如果用 DateTime picker，**必踩此坑**。

### 4.2 Replace 链格式化日期

教务数据日期格式可能不统一（ISO 带 T、斜杠、横杠等），同步时必须统一格式化：

```nasl
// 通用格式化链：斜杠→横杠 + 去T + 去.000Z
fmtStart = Replace(Replace(Replace(Convert<String>(item.periodStart), '/', '-'), 'T', ' '), '.000Z', '')
```

**⚠️ 复制粘贴必查**：Replace 的第 2、3 个参数是否正确，不要出现 `Replace(x, '-', '-')` 这种无效替换。

### 4.3 CW 内部 JVM/MySQL 时区不一致

**问题**：CW 内部 JVM 时区是 UTC，但 CW 内部 MySQL 时区是 +08:00。`FromString<DateTime>` 按 UTC 解析，JDBC 按 +08:00 写入 → **两次时区转换叠加 = +8h 偏移**。

**判断方法**：如果 CW 同步 DateTime 字段后，存入数据库的时间比源数据多了 8 小时，就是这个原因。

**解法**：
1. 优先方案：DateTime 字段改为 String 类型存储（避免时区转换）
2. 备选方案：Java 扩展逻辑减 8h 抵消偏移（见 4.1）

**讲义系统适用性**：教务库的日期字段同步到 CW 时，如果 CW 实体用 DateTime 类型，**必偏 +8h**。建议 CW 侧日期字段用 String 类型。

### 4.4 统一时钟源原则

**核心**：所有时间判断必须统一用 MySQL NOW()，不能混用多台机器的时间。

| 组件 | 时间源 | 说明 |
|------|--------|------|
| 前端时间判断 | `/api/time` → MySQL NOW() | 用服务器时间校正本地偏差 |
| 后端时间判断 | MySQL NOW() | 与业务时间直接比对 |
| 前端 `/api/time` | MySQL NOW(3) | 统一时钟源 |

**讲义系统适用性**：如果有"截止时间判断"等逻辑，必须统一时钟源。

---

## 五、CW SQL 查询踩坑

### 5.1 漏 is_delete 条件导致统计错误

```sql
-- ❌ 错误：把已软删除的记录也统计进去
COUNT(CASE WHEN a.status IN (1, 3) THEN 1 END) AS registered

-- ✅ 正确：加 AND a.is_delete = 0
COUNT(CASE WHEN a.status IN (1, 3) AND a.is_delete = 0 THEN 1 END) AS registered
```

**检查清单**：所有涉及有 `is_delete` 字段的表的统计查询，**必须加 `is_delete = 0` 条件**。

**讲义系统**：`jygl_lecture_approval` 和 `jygl_material_file` 都有 `is_delete` 字段，统计查询必加。

### 5.2 JOIN 行倍增导致 COUNT 翻倍

**问题**：一个班级有多条类别记录，LEFT JOIN 后每条报名记录被复制成多行，COUNT 翻倍。

**解法**：统计类 SQL（COUNT/SUM/GROUP_CONCAT）必须隔离到子查询里先聚合，再跟主表 JOIN：

```sql
-- ❌ 错误：COUNT 和 GROUP_CONCAT 在同一层级
LEFT JOIN ssc_class_category cc ON c.id = cc.class_id
LEFT JOIN ssc_categories cat ON cc.category_id = cat.id
GROUP BY ..., GROUP_CONCAT(DISTINCT cat.name ...)

-- ✅ 正确：每个聚合字段先在子查询里算好
LEFT JOIN (
    SELECT class_id, COUNT(*) FROM ssc_applications WHERE is_delete = 0 GROUP BY class_id
) app_stats ON c.id = app_stats.class_id
LEFT JOIN (
    SELECT cc.class_id, GROUP_CONCAT(DISTINCT cat.name SEPARATOR ', ')
    FROM ssc_class_category cc JOIN ssc_categories cat ON cc.category_id = cat.id
    GROUP BY cc.class_id
) cat_names ON c.id = cat_names.class_id
```

**讲义系统**：讲义审批表关联文件表（1:N），统计文件数时必须用子查询隔离。

### 5.3 SQL 聚合返回 AStructure vs List

**问题**：SQL 聚合查询无 GROUP BY 时返回单行，CW 识别为 `AStructure`，但表格组件只认 `List`。

**解法三步走**：
1. SQL 用 `UNION ALL` 把统计值拼成多行
2. 用 `ListFilter` 按 key 过滤取值
3. 返回 `List<结构体>`

```nasl
// SQL 返回 List<{ statKey: String, statValue: Integer }>
variable1 = sql"SELECT 'admitted' AS statKey, COALESCE(SUM(...), 0) AS statValue
    FROM jygl_lecture_approval WHERE is_delete = 0
    UNION ALL SELECT 'rejected' AS statKey, COALESCE(SUM(...), 0) AS statValue
    FROM jygl_lecture_approval WHERE is_delete = 0"

// 提取各统计值
admitted = Get(ListFilter(variable1, { item => item.statKey == 'admitted' }), 0).statValue
rejected = Get(ListFilter(variable1, { item => item.statKey == 'rejected' }), 0).statValue

// 返回 List（前端 current.item.属性名 直接访问）
result = [{ admitted=admitted, rejected=rejected }]
```

---

## 六、CW 接口与数据结构踩坑

### 6.1 API 返回字段 ≠ JSON 文件字段

**问题**：CW 导入的 JSON schema 里的字段不一定和实际接口返回一致。

**排查方法**：用 curl 调接口，看实际返回的 JSON key：
```bash
curl ... | python -c "import sys,json; d=json.load(sys.stdin); print(list(d['data'][0].keys()))"
```

**教训**：JSON schema 文件必须基于**实际接口返回**来写，不能凭"应该有"推断。

**讲义系统**：调鸿翼 API 或教务接口时，先 curl 确认实际返回字段，再写 JSON schema。

### 6.2 JSON schema type 与实际返回类型匹配

**问题**：`status` 字段在 JSON 里写 `"type": "integer"`，但实际返回 `"1"`（string），CW 导入后类型不匹配。

**教训**：接口文档里的 type 必须和实际返回的 JSON value 类型一致，不能按"业务含义"推断。

### 6.3 外网写入 vs 内网只读字段判断

**判断原则**：看这个字段谁生成、谁修改、谁只读：

| 字段类型 | 产生方 | 存储方 | 同步方向 |
|---------|--------|--------|---------|
| 教务自动生成（如学年） | 教务系统 | 教务写入，CW 只读 | 教务→CW（GET/直连） |
| CW 管理员操作（如审批状态） | CW | CW 写入 | 不从教务同步 |

**讲义系统**：教务数据全部是"教务写入、CW 只读"，CW 自建的 `jygl_lecture_approval` 等表的审批状态字段不从教务同步。

### 6.4 强类型 vs 动态类型（null 万能值）

**问题**：CW 调外部 API 时，如果响应 data 字段声明为 String 但实际返回对象，Jackson 反序列化直接崩溃。

**解法**：如果 CW 不需要读响应 data，后端接口返回 `data: null`。**null 是唯一兼容所有 Java 引用类型的值**。

**教训**：同一个接口，前端（JS）调没问题，CW（Java）调可能报错。排查时要考虑调用方的语言类型系统差异。

### 6.5 加新字段标准流程

后端/数据源新增字段后，CW 侧按以下顺序改：

| 步骤 | 操作 |
|------|------|
| ① | 生成新 JSON 接口文件（或确认数据源字段变更） |
| ② | CW 导入 JSON → 更新数据结构（data2 等） |
| ③ | NASL 代码加字段：`Add(data2, { ..., newField=source.newField })` |
| ④ | 检查 if 条件：比较逻辑是否缺新字段 |
| ⑤ | 检查 Body 传参：是否漏了新字段 |
| ⑥ | 检查拼写：I vs l（小写 L vs 大写 I）、小驼峰等 |

**拼写高危项**：`innerId` vs `innerld`（I 和 l 在 CW 字体下看起来一样），复制字段名时直接从 JSON 拷贝，不要手打。

### 6.6 OpenAPI 导入文件写法规范（🔴 反复踩过 3 次：09-01 / 09-03 / 09-10）

**背景**：CodeWave「集成中心 → 接口分组 → 导入」上传的 OpenAPI JSON，格式稍有偏差就会**生成空白结构体（blankobject）**或**字段类型错**。同类问题 09-01、09-03、09-10 各复发一次，故固化为以下规范。

#### 铁律 1：必须「全内联」，禁用 `$ref`

❌ 直接导官方 swagger → 崩。原因：官方用 `$ref` 且 key 是**含点号 + 反引号的 .NET 强名**：

```
#/components/schemas/FlatDms.GlobalDependency.CommonDto.ResultValue`1[[FlatDms.SDK.Dto.Perm.Dto.PermissionListResultDto, FlatDms.SDK.Dto, Version=1.0.0.0, ...]]
```

CodeWave 解析不了 ⇒ 模型建出来了但 **properties 全空**（表现为 `blankobject` / 三个模型都没参数）。

✅ 正确：`requestBody.schema` / `responses.schema` 直接把 `type: object` + `properties` 写进去，数组 `items` 内联 object，`components.schemas = {}`，`content` 只留 `application/json`。
👉 参考已验证模板：`讲义管理系统资料/output/swagger_权限接口_v2.json`（`s0470df…` 就是用它导入成功的）

#### 铁律 2：字段必须从 `swagger.json` 的 `components.schemas` **拷**，不能手写

手写必然漏字段（09-10 实测：手写了一版 `PermissionListModel` 只写 13 个，官方是 **26 个**，漏 `entryType`/`parentId`/`parentName`/`permFileVers`/`permFileAttachs`/`orig*` 系列 9 个）⇒ 导入后结构体缺字段，取值返回 null。

```bash
# 从官方 swagger 抄字段（别肉眼对着文档敲）
python -c "
import json,io
s=json.load(io.open('swagger.json',encoding='utf-8'))['components']['schemas']
print(list(s['FlatDms.SDK.Dto.Perm.Dto.PermissionListModel']['properties'].keys()))"
```

#### 铁律 3：不许出现「空 object」

`{"type":"object"}` 后面**不带 `properties`** = blankobject 的同型写法（06-01 坑的触发条件）。
典型翻车点：数组元素的 items 图省事写成 `{"type":"object"}`（如 `hiddenPermissions.items`）。**要跟同类型的兄弟字段写一样**。

#### 铁律 4：不写 `format`

`"type":"integer","format":"int32"` 里的 `format` 对 CodeWave 无增益，反而多一个解析分支。已验证模板里**没有** `format`，对齐它。

#### 铁律 5：GET + query 接口天然规避「Body 包层」坑

09-03 的 `DownloadCheck` 死结（Body 被解析成 `DownloadCheckBody{body:string}` → 序列化必包层 `{"body":…}` → 鸿翼 614），只出现在 **POST + requestBody**。如果是 GET + query（如 `LoadFolderPermission`），**不写 `requestBody`**、参数放 `parameters`（`in: query`）即可绕开。

#### 铁律 6：编码格式

- UTF-8 **无 BOM**（有 BOM 首字段解析失败）
- 换行 **LF**（勿混 CRLF）
- description 用常规中英文标点，**避免 `★ ⇒ ①② 「」` 等非常规符号**（降编码风险）

#### 导入前 6 项自查（脚本化，一次跑完）

```bash
python - <<'EOF'
import json,io
f='xxx_导入.json'; d=json.load(io.open(f,encoding='utf-8')); raw=open(f,'rb').read()
def scan(o,h,p='root'):
    if isinstance(o,dict):
        for k,v in o.items():
            if k=='$ref': h.append(('$ref',p))
            if k=='format': h.append(('format',p))
            if k=='type' and v=='object' and 'properties' not in o and 'items' not in o: h.append(('空object',p))
            scan(v,h,p+'.'+k)
    elif isinstance(o,list):
        for i,v in enumerate(o): scan(v,h,p+f'[{i}]')
h=[]; scan(d,h)
print('① BOM:', 'FAIL' if raw[:3]==b'\xef\xbb\xbf' else 'OK')
print('② 换行:', 'FAIL' if b'\r\n' in raw else 'OK')
print('③ 结构问题:', h or 'OK（无 $ref/format/空object）')
print('④ components.schemas 为空:', 'OK' if not d['components']['schemas'] else 'FAIL')
print('⑤ paths:', list(d['paths'].keys()))
print('⑥ 体积:', len(raw),'bytes')
EOF
```

> 09-10 实战：`swagger_权限查询_导入.json` 按上述 6 条修完（26 字段全等 + 两处 items 同类型 + 去 format + 去特殊符号），产物体积 19 KB、扫描零问题。生成脚本思路见该文件的 git 历史/本条记录。

---

## 七、CW Java 扩展逻辑

### 7.1 注册机制：一个节点 = 一个入口方法

**核心规则**：
1. CW 的 Java 扩展逻辑是 **IDE 节点注册机制**，不是标准 Spring Bean 发现
2. **一个扩展逻辑节点 = 一个入口方法**，不是"一个类 = 多个方法随便调"
3. `Javalogic1Service` 只注册"逻辑树节点对应的入口方法"
4. **入口方法名称必须跟 Java 扩展逻辑名称保持大小写一致**

**新建 Java 扩展逻辑的正确步骤**：
1. CW IDE 左侧逻辑树 → "扩展逻辑"节点 → **右键 → 添加扩展逻辑**
2. 逻辑名设为和 Java 入口方法名一致（大小写敏感）
3. **添加输入参数、输出参数**（在左侧树节点右键添加，设置数据类型）
4. 在编辑区写 Java 代码，入口方法签名和参数顺序要跟 IDE 里设置的一致
5. **检查类名属性**：IDE 操作页有一行类名，必须改成完整包名+类名
6. 保存 → 编译

**常见错误**：
- ❌ 只在已有 Java 扩展逻辑类里加新方法 → Javalogic1Service 不注册 → `cannot find symbol`
- ❌ 新建了 Java 类但没在 IDE 逻辑树里添加扩展逻辑节点 → 同上
- ❌ 新建了扩展逻辑节点但类名属性没改 → Javalogic1Service 找不到方法

### 7.2 不需要 @NaslLogic 注解

```java
// ❌ 不需要 @NaslLogic
// ❌ 不需要 import nasl.gen.annotation.NaslLogic

@Service
public class ConvertUtcToLocal {
    // 纯 public 方法即可被 NASL 调用
    public String convertUtcToLocal(String utcString) { ... }
}
```

**NASL 调用**：
```nasl
result = app::logics::ConvertUtcToLocal::convertUtcToLocal(input)
```

### 7.3 String.format %d 收到 String 崩溃

```java
// ❌ 错误：%d 期望 int，但 minute/second 是 String
String correctTime = String.format("%02d:%02d:%02d", correctHour, minute, second);

// ✅ 正确：用字符串拼接，不用 String.format
String finalHour = correctHour < 10 ? "0" + correctHour : "" + correctHour;
String correctTime = finalHour + ":" + minute + ":" + second;
```

**教训**：Java `String.format` 的 `%d`/`%x`/`%f` 严格检查类型，收到 String 直接抛异常。处理字符串时统一用拼接。

---

## 八、讲义系统教务数据同步设计建议

### 8.1 同步架构

```
教务系统 MySQL (<内网地址·已脱敏>:6001, 〈教务库〉)
    │
    │ CW 数据源直连（已配置）
    ▼
CodeWave 本系统
    ├── 手动同步：管理员点"同步"按钮
    └── 定时同步：CW cron 定时任务（建议每天凌晨 2:00）
```

### 8.2 需要同步的教务表

| 教务表 | CW 用途 | 同步方式 | 过滤条件 |
|--------|---------|---------|---------|
| `sys_academic_year` | 学年学期下拉 | 全量覆盖 | 无 |
| `sys_department_information` | 学院/系部树 | 全量覆盖 | `type IN (0,1,2)`（学院/系/部） |
| `sys_teacher_info` | 教师选择器 | 全量覆盖 | 无（全量几千行） |
| `tpm_course_table` | 课程选择器 | 全量覆盖 | 无 |
| `tpm_approval_set` | 课程负责人映射 | 全量覆盖 | `task_user3 IS NOT NULL` |
| `csm_teaching_task` | 教学任务/教学班 | 全量覆盖 | `is_delete = 0`，可选 `stop_type IS NULL` |
| `csm_teaching_teacher_map` | 教学班↔教师 | 全量覆盖 | 跟随教学任务过滤 |
| `csm_teaching_class_map` | 教学班↔行政班 | 全量覆盖 | 跟随教学任务过滤 |
| `tpm_course_replace_code` | 课程替换映射 | 全量覆盖 | 无 |

### 8.3 CW 侧表设计建议

教务数据在 CW 侧建议建**镜像表**（前缀 `jygl_`），字段与教务表一一对应，但：

1. **日期字段用 String 类型**（避免 CW JVM/MySQL 时区不一致导致偏移，见 4.3）
2. **加 `sync_time` 字段**（DATETIME，记录最后一次同步时间，便于排查）
3. **不加业务逻辑字段**（审批状态等放在 `jygl_lecture_approval` 主表，不混在教务镜像表里）

### 8.4 同步逻辑 NASL 伪代码框架

```nasl
logic syncAcademicData() => result: String {
    // ① 全量覆盖：sys_academic_year
    JyglAcademicYearEntity::deleteBy(JyglAcademicYear => true)
    outerYears = sql"SELECT academic_year, semester, ... FROM sys_academic_year"
    for (item in outerYears) {
        JyglAcademicYearEntity::create({
            academicYear=item.academicYear,
            semester=item.semester,
            syncTime=CurrentDateTime()
        })
    }

    // ② 全量覆盖：sys_department_information（带过滤）
    JyglDepartmentEntity::deleteBy(JyglDepartment => true)
    outerDepts = sql"SELECT department_id, department_name, ... FROM sys_department_information WHERE type IN (0,1,2)"
    for (item in outerDepts) {
        JyglDepartmentEntity::create({...})
    }

    // ③ 全量覆盖：sys_teacher_info
    // ... 同上模式

    // ④ 全量覆盖：csm_teaching_task（带过滤）
    JyglTeachingTaskEntity::deleteBy(JyglTeachingTask => true)
    outerTasks = sql"SELECT ... FROM csm_teaching_task WHERE is_delete = 0"
    for (item in outerTasks) {
        JyglTeachingTaskEntity::create({...})
    }

    // ⑤ 关联表跟随主表过滤
    // ...

    result = '同步成功'
}
```

### 8.5 定时同步 cron 建议

| 频率 | cron 表达式 | 说明 |
|------|-----------|------|
| 每天凌晨 | `0 0 2 * * ?` | 凌晨 2:00 执行，避开教学时段 |
| 每小时 | `0 0 * * * ?` | 数据变更频繁时用 |

**注意**：教务数据变更频率低（每学期初集中调整），建议每天一次即可。

### 8.6 同步注意事项

1. **deleteBy 前先确认数据量**：如果教务库连接异常导致查到 0 条，deleteBy 会清空 CW 侧所有数据。建议加保护：
   ```nasl
   if (Length(outerYears) > 0) {
       JyglAcademicYearEntity::deleteBy(JyglAcademicYear => true)
       for (item in outerYears) { JyglAcademicYearEntity::create({...}) }
   }
   ```

2. **同步顺序**：被依赖的表先同步（见 8.2 顺序），否则外键/关联会断

3. **同步期间页面可能短暂无数据**：全量覆盖的 truncate→insert 之间有短暂窗口，如果用户此时访问页面会看到空数据。对于讲义系统（内部使用、凌晨同步），影响可忽略

4. **教务库连接稳定性**：CW 数据源直连教务库，如果教务库维护/重启，同步会失败。建议同步逻辑加 try-catch，失败时记录日志但不影响 CW 侧已有数据

5. **字段名映射**：教务库字段名是下划线（`academic_year`），CW 实体属性是小驼峰（`academicYear`），CW ORM 自动转换，NASL 代码用小驼峰

---

## 附录：快速检查清单

写 CW NASL 同步逻辑时，逐条过一遍：

- [ ] List/Map 声明是否初始化了 `= []` / `= {}`
- [ ] 循环内全局变量是否每轮重置
- [ ] Add 是否在内层循环外部（只执行一次）
- [ ] Map 判断是否用 MapContains（不是 == null）
- [ ] 嵌套循环 index 是否各层不同名
- [ ] else 分支变量是否重置
- [ ] Entity{} 字面量是否覆盖了前置赋值
- [ ] deleteBy filter 是否用平台自动生成变量名
- [ ] 日期字段是否用 String 类型（避免时区偏移）
- [ ] DateTime picker 输出是否用 convertUtcToLocal 转换
- [ ] SQL 统计是否加了 is_delete = 0
- [ ] SQL COUNT 是否被子查询隔离（防 JOIN 倍增）
- [ ] SQL 聚合无 GROUP BY 是否用 UNION ALL 转 List
- [ ] JSON schema 是否基于实际 curl 返回（不是凭推断）
- [ ] 新字段是否走完 6 步标准流程
- [ ] Java 扩展逻辑是否在 IDE 添加了节点 + 改了类名属性
- [ ] 同步前是否检查了数据量保护（空数据不 truncate）
- [ ] 同步顺序是否按依赖关系排列
