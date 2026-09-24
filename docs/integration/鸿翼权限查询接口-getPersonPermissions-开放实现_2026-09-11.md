# 鸿翼「查询某人有什么权限」· 开放接口实现（`getPersonPermissions`）

> 需求（主人 2026-09-11）：现有 3 个开放接口（`grantResidentL1` / `grantResidentL2` / `removePersonPermission`）之上，
> 再开放**一个查询接口**：**输入 userId（工号）→ 返回这个人在鸿翼上有哪些目录授权**。
>
> 落地位置：与管理鸿翼权限的**同一个 CodeWave 应用**（`jyglqxcx`），与现有三接口同域名、同鉴权。
> 设计源头：`docs/鸿翼权限管理四接口-设计与实现_2026-09-10.md` §四（接口①）。本文是**可直接照做的定稿版**。
>
> ⚠️ CodeWave 逻辑只能拖组件，下文 NASL 是**逻辑等价参考**，实际按 §五「拖组件蓝图」操作。
>
> **📌 状态（09-11 18:10 更新）**：✅ 逻辑已拖完 → ✅ 8 轮核对通过（§3.7）→ ✅ **已开放为接口** → ✅ **应用已发布** ⇒ 🔴 **只剩最后一步：用有 ≥2 条权限的工号外调一次**（**1 条命中查不出逗号问题**）。§三 定稿 NASL 与平台拖出版**逐字一致**，**勿再改动**；对外契约 = 桌面《四个开放接口的使用说明文档.md》**v2.8**。

---

## 一、接口契约（定稿）

| 项 | 内容 |
|---|---|
| 逻辑名 | `getPersonPermissions` |
| 对外路径 | `GET {制品域名}/rest/getPersonPermissions` |
| 用途 | 查某人在鸿翼目录上的**直接授权**清单（供管理端核对 / 清权前预检） |
| 入参 | `employeeId : String`（工号，**必填**）<br>`scope : String = 'resident'`（**有默认值 ⇒ 可选**） |
| 出参 | `result : String`（**JSON 字符串**，🔴 与另外三个接口的「中文文案」不同，见 §七） |

**关于参数名 `employeeId` vs 需求说的 `userId`**

需求原文写 `userId`，但**现有 3 个接口全部用 `employeeId`**，且三者口径一致：
`userId` = `employee_id` = `currentUser.userId` = **工号**（不是鸿翼 `identityId`）。
接口内部用 `getIdentityIdByAccount` 把工号转成鸿翼 `identityId`，**调用方不需要知道鸿翼 id**。

⇒ **保持 `employeeId`**，不引入第二个概念（09-10 已就此拍板，见四接口设计文档 §二末）。
若对接方坚持要 `userId`，在逻辑里把入参改名即可，**逻辑体一个字都不用动**。

**`scope` 取值**

| 值 | 覆盖层级 | 目录条数 | 耗时 |
|---|---|---|---|
| `resident`（**默认**） | L1 应用 + L2 学院（常驻授权范围） | 约 10~20 | 秒级 ✅ |
| `all` | 再加 L3 学年 + L4 课程（逐课授权在这） | 可能上百 | 1~4 分钟 ⚠️ 有超时风险 |

> 🔴 开放为 HTTP 后 `all` **很可能被网关/平台超时打断**。查逐课 L4 权限请走**定向**思路（见四接口文档附录 A），不要靠全扫。

---

## 二、前置三步（🔴 不做完，逻辑拖不出来）

| # | 动作 | 位置 | 状态 |
|---|---|---|---|
| 1 | 导入 `讲义管理系统资料/output/swagger_权限查询_导入.json`（19 KB，v1.0.1，全内联已校验） | 集成中心 → 接口分组 → **`jyglqxcx`（讲义管理权限查询API）** → 导入 | ⬜ 待做 |
| 2 | 新建结构体 `app::structures::HyPermHit` | 应用 → 数据结构 → 新建 | ⬜ 待做 |
| 3 | 确认本应用能连**讲义库** `JyglHyFolderMap` | 数据源配置 | ✅ 已证（现有 `removePersonPermission` 就在查这张表） |

**`HyPermHit` 字段（4 个，①③ 共用）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `folderId` | String | 目录 id（库里 VARCHAR，🔴 不要用 Integer） |
| `pathKey` | String | 目录路径名（如 `计算机学院|2025-2026-1|J9041002`），**管理端显示用** |
| `permCateId` | Integer | 该人在这条目录上的**真实**权限类别（8/9/12…） |
| `permType` | Integer | 10 = 分配权限 / 20 = 流程权限 |

> 💡 `pathKey` 是相对原设计新增的字段——查询接口的价值就是给人看目录名，光返 folderId 没法核对。
> 它顺带给后续 `removePersonPermission` 改造复用，不用再建第二个结构体。

导入后确认：接口分组里出现 **`LoadFolderPermission`**（`GET /PermList/LoadFolderPermission`，query: `token` + `folderId`）。

---

## 三、定稿 NASL（逻辑等价参考）

> ⚠️ CodeWave 的 NASL **只读、不能直接粘贴**，只能照它拖组件。下文的作用是把每一步的语义讲清，落地按 §五 拖组件蓝图。

### 3.1 变量明细表（拖之前先把这些变量建出来）

**入参 / 出参**

| 变量名 | 类型 | 初始值（写死） | 用途 |
|---|---|---|---|
| `employeeId` | String | ——（**必填入参**） | 被查询人**工号**；接口内部转鸿翼 `identityId`，调用方不需要知道鸿翼 id |
| `scope` | String | **`'resident'`**（入参默认值） | 扫描范围：`resident`=L1+L2 / `all`=L1~L4。🔴 **必须设默认值**，否则开放后它变必填 ⇒「只传工号也能调」不成立 |
| `result` | String | ——（出参） | 返回的 **JSON 字符串**（与另外三个接口返中文文案不同） |

**局部变量（12 个，全部在逻辑开头声明 + 初始化；另有 `b` / `lb` 两个可选备胎）**

| 变量名 | 类型 | 初始值（写死） | 用途 |
|---|---|---|---|
| `tok` | String | `''` | 鸿翼 file 服务账号 token。★ **循环外取一次，全程复用** |
| `identityId` | List\<Integer\> | 不给（`let identityId: List<Integer>;`） | `getIdentityIdByAccount` 的返回：工号对应的鸿翼人员 id 列表 |
| `idInt` | Integer | `0` | 被查人的鸿翼数字 id = `Get(identityId, 0)`，循环内比对基准 |
| `scanFolders` | 匿名结构体列表 | `[]`（类型由平台推断） | 待扫描目录清单，`SELECT * FROM JyglHyFolderMap` 的结果 |
| `permResp` | 接口响应结构 | —— | `LoadFolderPermission` 响应（含 `result` / `reason` / `data`） |
| `permList` | 结构体列表 | `[]`（类型由平台推断） | 当前目录的授权明细 = `permResp.data.permissions` |
| `hitCount` | Integer | `0` | 命中条数（最终 JSON 的 `count`） |
| `json` | String | `''` | `permissions` 数组的内容片段 |
| `sep` | String | 🔴 **`''`（空串，不是 `','`）** | 「**本条记录前面要加的分隔符**」：首条为空串、其后 `','`。**初值 `''` + 循环末尾 `sep = ',';`** 两处配合才行（见 §3.7 第三轮修正 P0-1/P0-2） |
| `permCateStr` | String | `''` | 权限类别转字符串（拼 JSON 用） |
| `permTypeStr` | String | `''` | 权限来源转字符串（拼 JSON 用） |
| `q` | String | `'"'`（**一个双引号字符**） | 🔴 **仅方案 B 需要**。`s"…"` 模板里不能出现裸双引号 ⇒ 用 `${q}` 代替（见 §3.7）。⚠️ ⛔ **不要**用它包数值（`permCateId` / `permType` / `identityId`） |
| `b` | String | `'}'`（**一个右花括号字符**） | ⚪ **可选，默认不用建**。仅当模板里的**裸 `}`** 报错时才加，用 `${b}` 顶替（见 §3.7 P0-3）。裸 `}` 能过就直接写 `}` |
| `lb` | String | `'{'`（**一个左花括号字符**） | ⚪ **可选，默认不用建**。仅当模板**开头**的裸 `{` 报错时才加，用 `${lb}` 顶替（见 §3.7 P0-4）。优先直接写 `{` |
| `hitList` | `List<app::structures::HyPermHit>` | `[]: List<app::structures::HyPermHit>` | 命中结果集合。🔴 **必须初始化为 `[]`**，否则 `Add` 无效 ⇒ **永远 `count:0`** |

**循环变量（3 个，由 ForEach 生成；三处引用必须同名）**

| 变量名 | 来源 | 用途 |
|---|---|---|
| `folderRow` | `scanFolders` 的循环项 | 当前目录（取 `.folderId` / `.pathKey`） |
| `permRow` | `permList` 的循环项 | 当前授权明细项（比对 `.memberId` / `.memberType` / `.entryId`） |
| `hitRow` | `hitList` 的循环项 | 当前命中项（拼 JSON 用） |

> 🔴 平台拖出来的循环头**默认叫 `item` / `item1` / `Item`**。要么三个循环全用平台默认名，要么手动改成上表语义名并**同步全部引用点** —— **关键不是叫什么，而是三处引用同名**（这是"永远 `count:0`"的头号原因）。

### 3.2 完整 NASL（逐行注释）

```nasl
using nasl::core;
using nasl::collection;
using nasl::util;

@(description = '查询某工号在鸿翼目录上的直接授权清单（开放为接口供外部调用）')
logic getPersonPermissions(employeeId: String, scope: String = 'resident') => result: String {

    /* ==================== 一、变量声明（全部在逻辑开头声明） ==================== */
    /* 🔴 声明语法 = `let`（不是 `declare`）。平台生成的形式有三种，都合法：
          `let x;`  /  `let x: T;`  /  `let x: T = 初值;`
          规律：List/Map **要在循环里 Add 就必须给初值**（`= []: List<T>`）；只被赋值一次的（如 tok）平台生成 `let tok;` */
    let tok;                                                 // 鸿翼 file 服务账号 token（hyGetToken 取得，★全程复用）
    let identityId: List<Integer>;                           // 工号 → 鸿翼人员 id 列表（getIdentityIdByAccount 返回）
    let idInt: Integer = 0;                                  // 被查人的鸿翼数字 id（取 identityId 第 0 个），比对基准
    let scanFolders;                                         // 待扫描目录清单（SQL SELECT * 结果，类型由平台推断）
    let permResp;                                            // LoadFolderPermission 响应（含 result / reason / data）
    let permList;                                            // 当前目录的授权明细 = permResp.data.permissions
    let hitCount: Integer = 0;                               // 命中条数（最终 JSON 的 count）
    let json: String = '';                                   // permissions 数组的内容片段
    let sep: String = '';                                    // 逗号分隔符：首条为空串，其后为 ','（自己控逗号）
    let permCateStr: String = '';                            // 权限类别转字符串（拼 JSON 用）
    let permTypeStr: String = '';                            // 权限来源转字符串（拼 JSON 用）
    let hitList: List<app::structures::HyPermHit> = []: List<app::structures::HyPermHit>;
                                                             // 🔴 命中集合：必须初始化为 []，否则 Add 无效 → 永远 count:0

    /* ==================== 二、入参校验：工号为空直接返回 ==================== */
    if (!HasValue(employeeId)) {                             // 工号必填；判空只用 HasValue（见 §五 必查 4）
        result = '{"code":1,"msg":"参数错误：employeeId 为空"}';   // 静态 JSON 用单引号包，内部双引号不必转义
        end;                                                 // 终止逻辑（end = 不再往下走，≠ return）
    }
    /* ⛔ 不要写 `} else { employeeId = employeeId; }` 这类自赋值占位！
       NASL 的 if **允许没有 else**（`grantResidentL1` 实测：`if (…) { result=…; end; }` 后直接接下一个 if）。
       实在想保留对称结构，写空块 `} else { }`（09-10 版实测过）—— 自赋值是纯噪音。 */

    /* ==================== 三、工号 → 鸿翼 identityId（★ 循环外，只登一次） ==================== */
    tok = app::logics::hyGetToken(undefined);                // 🔴 全逻辑只取一次：hyGetToken 每次都真登录，
                                                             //    同账号再登会作废旧 token ⇒ 循环外取、循环内透传
                                                             // 🔴 必须显式传 undefined（项目三处实测写法），别写空参 ()
    identityId = app::logics::getIdentityIdByAccount(tok, employeeId);  // 工号 → 鸿翼 person id 列表
    if ((!HasValue(identityId)) || (Get(identityId, 0) <= 0)) {         // 查空 或 首个 id 非法 ⇒ 人员不存在
        result = '{"code":1,"msg":"解析人员失败:' + employeeId + '"}';   // 用 + 拼接，避免模板里嵌套双引号
        end;
    } else {
        idInt = Get(identityId, 0);                          // 取第 0 个 identityId 作为比对基准
    }

    /* ==================== 四、按 scope 定扫描范围，查目录清单 ==================== */
    if (scope == 'all') {
        /* all：L1应用 + L2学院 + L3学年 + L4课程（逐课授权在这层）
           目录可能上百 ⇒ 串行约 0.3s/个 ⇒ 分钟级，开放成 HTTP 后有超时风险 */
        scanFolders = sql"SELECT * FROM JyglHyFolderMap WHERE isDelete = 0 AND level IN (1,2,3,4)";
    } else {
        /* resident（默认）：只扫 L1 + L2 常驻授权范围（约 10~20 个目录，秒级） */
        scanFolders = sql"SELECT * FROM JyglHyFolderMap WHERE isDelete = 0 AND level IN (1,2)";
    }
    if (!HasValue(scanFolders)) {                            // 目录表查空 ⇒ 环境/数据源问题，≠「这人没权限」
        result = '{"code":2,"msg":"目录映射表无数据"}';
        end;
    }

    /* ==================== 五、逐目录查权限，只收「本人 + 个人授权 + direct」 ==================== */
    for (folderRow in scanFolders, index in 0) {             // 遍历目录（循环变量名与下方 3 处引用必须同名）
        /* 🔴 循环内只「调用接口」，不「调用逻辑」（平台红线：循环内禁调服务端逻辑）
           🔴 folderId 列库内是 VARCHAR，而接口入参是 integer ⇒ 必须 Convert<Integer>
           🔴 传循环外取好的 tok，不在循环内重复登录 */
        permResp = apis::jyglqxcx::interfaces::sb411ad07173f4b4b4c47f8871a266abf(
            token    = tok,
            folderId = Convert<Integer>(folderRow.folderId),
        );
        /* ⚠️ 若 IDE 拖出来发现签名里多一个 `Content_Type`（平台统一生成的 header 参数，与 swagger 无关），
           就在 folderId 后面补一行 `Content_Type = undefined,`（GET 无 body ⇒ 不发这个头）。
           09-10 实测版**没有**这个参数 ⇒ **以 IDE 实际签名提示为准**。 */

        if (permResp.result == 0) {                          // 0 = 查询成功；801 = 目录不存在（当轮跳过）
            permList = permResp.data.permissions;            // 该目录的全部授权明细
            if (HasValue(permList)) {                        // 明细非空才继续；判空只用 HasValue
                for (permRow in permList, index in 0) {      // 遍历该目录的授权明细
                    /* 三个条件同时成立才算命中：
                       ① permRow.memberId   == idInt              → 是"这个人"
                       ② permRow.memberType == 1                  → 是"个人授权"（2部门/4职位/8用户组 不算）
                       ③ permRow.entryId    == folderRow.folderId → 是"直接授权"
                          （继承来的项 entryId 指向别的目录 ⇒ 本接口故意不报，符合设计）
                       ⚠️ entryId 官方类型是 string，folderRow.folderId 也是 String ⇒ 直接比，⛔ 不要 Convert */
                    if (((permRow.memberId == idInt) && (permRow.memberType == 1)) && (permRow.entryId == folderRow.folderId)) {
                        Add(hitList, app::structures::HyPermHit {     // 收进命中集合（结构体字面量，09-10 版实测写法）
                            folderId   = folderRow.folderId,          // 目录 id（String，⛔ 不要转 Integer）
                            pathKey    = folderRow.pathKey,           // 目录路径名，管理端显示用
                            permCateId = permRow.permCateId,          // 真实权限类别：8仅预览/9预览+下载/12管理
                            permType   = permRow.permType,            // 10=分配权限 / 20=流程权限
                        });
                    }
                    /* 不命中 ⇒ 什么都不做，**不要写 else 占位** */
                }
                /* 该目录无授权明细 ⇒ 什么都不做 */
            }
        }
        /* 单目录失败（如 801）⇒ 静默跳过。🔴 绝对不要 end，否则一个坏目录毁掉整体结果 */
    }

    /* ==================== 六、拼 JSON（自己控逗号，不依赖 join） ==================== */
    for (hitRow in hitList, index in 0) {
        hitCount = hitCount + 1;                             // 计数 +1
        permCateStr = Convert<String>(hitRow.permCateId);    // 数值 → 字符串，拼 JSON 用
        permTypeStr = Convert<String>(hitRow.permType);
        json = json + sep + '{"folderId":"' + hitRow.folderId + '","pathKey":"' + hitRow.pathKey
             + '","permCateId":' + permCateStr + ',"permType":' + permTypeStr + '}';
        sep = ',';                                           // 从第二条起加逗号
    }

    /* ==================== 七、输出完整 JSON ==================== */
    result = '{"code":0,"employeeId":"' + employeeId + '","identityId":' + Convert<String>(idInt)
           + ',"scope":"' + scope + '","count":' + Convert<String>(hitCount) + ',"permissions":[' + json + ']}';
    end;
}
```

### 3.3 关于 JSON 拼接的两种写法

| 写法 | 说明 |
|---|---|
| **推荐：单引号字面量 + `+` 拼接**（§3.2 用的） | 静态部分用 `'{"code":1,...}'` 单引号包，内部双引号**不必转义**；变量用 `+` 拼进来；数值先 `Convert<String>` |
| **方案 B（平台强制 `s"…"` 时用）：双引号变量法** → 见 §3.7 | 加 `let q: String = '"';`，模板里**全部**用 `${q}` 代替双引号。🔴 `\"` 转义**已作废** —— 官方文档明确「文本组件不支持任何转义字符」 |

### 3.4 写法支持性核对（2026-09-11，逐条对官方文档 + 本项目实测）

> 结论：**§3.2 的 NASL 整体被平台支持**，语法均在 CodeWave 官方内置能力或本项目已跑通的代码里有先例。
> 依据分三类：**①官方文档**（codewave-brain 本地文档库）/ **②本项目实测**（`docs/` 里已发布跑过的 NASL）/ **③推断**。

| 写法 | 支持 | 依据 |
|---|---|---|
| `@(description = '…')` | ✅ | ② `grantResidentL1` / `addPersonPermission` 实测 |
| `logic name(a: T, b: T = 默认值) => result: String {` | ✅ | ② 默认值：`permCateId: Integer = 9`；出参带类型：`=> result: String {` |
| `let x;` / `let x: T;` / `let x: T = 初值;` | ✅ | ② 三种形式均在项目 NASL 里出现；① 官方"赋值/变量"组件 |
| `let list: List<T> = []: List<T>;` | ✅ | ② §5.83 实测：List/Map **要在循环里 Add 就必须给初值** |
| `end;` | ✅ | ② 项目大量使用。官方叫「**中止**」组件；`break` 才是跳出循环 |
| `if (…) { …; end; }`（**无 else**） | ✅ | ② `grantResidentL1` 连续两个无 else 的 if |
| `} else { }`（**空 else**） | ✅ | ② 09-10 四接口文档实测 |
| `else { x = x; }`（自赋值占位） | ⛔ 没必要 | 语法能过，但**平台拖不出来**、纯噪音 ⇒ 删掉 |
| `for (item in list, index in 0)` | ✅ | ② 09-10 版就是 `for (folderItem in scanFolders, index in 0)` |
| `break` / `continue`（跳出/继续循环） | ✅ | ① 官方循环组件；② §5.11 实测 |
| `sql"SELECT … ${var}"` | ✅ | ② `sql"SELECT folderId FROM JyglHyFolderMap WHERE level = 1 AND isDelete = 0 LIMIT 1"` |
| `Convert<Integer>(x)` / `Convert<String>(x)` | ✅ | ① 官方内置函数 `Convert`；② `fid = Convert<Integer>(folderId)` 实测 |
| `Get(list, 0)` / `Add(list, item)` / `HasValue(x)` | ✅ | ① 官方内置函数（列表函数 / 其他函数） |
| `apis::平台::interfaces::接口id(...)` 具名传参 + 尾逗号 | ✅ | ② `LoadFolderPermission` 调用实测 |
| `app::logics::逻辑名(...)` | ✅ | ② 项目大量使用 |
| `app::logics::hyGetToken(undefined)` | ✅ | ② 三处实测；**别写空参 `()`** |
| `app::structures::X { 字段 = 值, }` 结构体字面量 | ✅ | ② 09-10 版就是 `Add(hitList, app::structures::HyPermHit { … })` |
| `s"…${var}…"` 模板串 | ✅ | ② 项目权限接口全用它拼返回文案 |
| `'…' + var` 拼接 | ✅ | ① 官方算数运算 `+` 支持 String；项目用 `+` 拼日期字符串 |
| `==` `!=` `&&` `\|\|` `!` | ✅ | ② 项目实测。🔴 **双判时：否定用 `\|\|`、肯定用 `&&`**（互换即恒真/恒假，`HasValue('')` 为真） |
| `Length(x)` | ⚠️ 有条件 | ① `Length` 是**字符串函数**；对 `List<String>` 可用（② `Length(l1FolderId) <= 0` 实测），对 `List<结构体>` 报「参数类型不一致」⇒ **列表判空一律只用 `HasValue`** |
| `SELECT * FROM JyglHyFolderMap …` | ✅ | ② `SELECT * FROM JyglLectureGroup …` 实测。本逻辑要同时取 `folderId`+`pathKey`，**只能 `SELECT *`**（多列/自定义别名 = 幻影类型 `53724c75`） |

### 返回样例

```json
{"code":0,"employeeId":"41255","identityId":1208,"scope":"resident","count":2,
 "permissions":[{"folderId":"161","pathKey":"讲义管理","permCateId":9,"permType":10},
                {"folderId":"174","pathKey":"计算机学院","permCateId":9,"permType":10}]}
```

无权限时（**正常结果，不是错误**）：

```json
{"code":0,"employeeId":"99999","identityId":1301,"scope":"resident","count":0,"permissions":[]}
```

---

### 3.5 平台拖出版 vs 定稿版差异核对（2026-09-11，🔴 拖完必看）

把从平台实际拖出来的 NASL 与 §3.2 定稿逐行比对，**结论：结构、判空、循环、SQL 分支、比对条件全部正确**，但 **3 处必须修**（其中 2 处导致**编译不过**）：

| # | 位置 | 拖出版（❌） | 定稿版（✅） | 后果 |
|---|---|---|---|---|
| **P0-1** | 第六段拼 JSON | `json = s"${json}${sep}'{"folderId":"' + hitRow.folderId + '","pathKey":"${hitRow.pathKey}'","permCateId":'${permCateStr}',"permType":'${permTypeStr}";` | `json = json + sep + '{"folderId":"' + hitRow.folderId + '","pathKey":"' + hitRow.pathKey + '","permCateId":' + permCateStr + ',"permType":' + permTypeStr + '}';` | 🔴 **`s"…"` 模板与 `+` 拼接混用在同一条表达式里 ⇒ 语法不通**。`s"${json}${sep}'{"` 遇到第二个 `"` 字符串就结束了，紧随其后的 `folderId` 成裸标识符 ⇒ **编译不过**。且末尾**缺 JSON 右花括号 `}`** |
| **P0-2** | 第六段循环末尾 | **整行不存在** | `sep = ',';` | 🔴 `sep` 恒为空串 ⇒ **多条命中之间没有逗号**（`}{` 直接相粘）⇒ 产出的 JSON **非法，对接方解析必失败**。⚠️ 只有 1 条命中时看不出来 ⇒ **必须用 ≥2 条权限的账号测** |
| **P0-3** | 变量声明 | `let hitCount: Integer;` | `let hitCount: Integer = 0;` | 🔴 首次执行 `hitCount = hitCount + 1` 是 **null + 1** ⇒ 报错或得到非数字，`count` 字段失真 |
| **P1-1** | 变量声明 | `let permTypeStr: String;` / `let tok: String;` | 两个都给 `= ''` | ⚠️ 它们只在被赋值后才用，属**低风险**；但按约定"开头声明 + 初始化"应补齐 |
| **P1-2** | 第七段输出 | `result = s"'{"code":0,...' + employeeId + '","identityId":'${Convert<String>(idInt)}',...}'";` | `result = '{"code":0,"employeeId":"' + employeeId + '","identityId":' + Convert<String>(idInt) + ',"scope":"' + scope + '","count":' + Convert<String>(hitCount) + ',"permissions":[' + json + ']}';` | 🔴 同样是 **`s"` 与 `+` 混用** ⇒ 编译不过。（注：`${Convert<String>(idInt)}` 本身**没问题** —— 官方支持在文本里嵌入内置函数；这里只是混用的连带问题） |

**拖出版里"看着不一样但完全正确"的 5 处**（⛔ 不要再改回去）：

| 差异 | 说明 |
|---|---|
| `=> result: String = ''`（定稿写 `=> result: String`） | 给出参设了初值 —— **更好**（避免 result 为 null）。✅ 保留 |
| `} else { }` **空 else**（定稿是干脆不写 else） | 两者**等价**：NASL 的 `if` 允许没有 else，也允许空块。空 else 是平台「分支」组件的自然产物 ⇒ **保留无害**（见 §3.2 注释块） |
| `/* 注释 */;` 注释后带分号 | 平台「注释」组件生成的样式，是**空语句**，无害。✅ 保留 |
| `Add(...)` 里字段顺序 `folderId, permCateId, permType, pathKey` | 结构体字段赋值**与书写顺序无关**。✅ 保留 |
| `if` 中 `entryId==folderId` 与 `memberType/memberId` 的先后 | `&&` 可交换，**逻辑等价**。✅ 保留 |

> 🔴 **一句话规律（本次踩坑的根因）**：**JSON 拼接只能选一条路** —— 要么**纯 `+`**（§3.2 定稿走这条），要么**纯 `s"…"` 模板 + `\"` 转义**。**⛔ 两者绝不能混在同一条表达式里。**

---

### 3.6 🔴 三行「照抄版」（引号反复踩坑 ⇒ 直接对着这段打字）

> 背景：09-11 的**两版**拖出代码都在**同一处引号**上栽跟头。根因：JSON 里全是双引号，而 `s"…"` 模板**一旦遇到裸 `"` 字符串就结束**，紧随其后的内容立刻变成非法语法。
> **结论：这三行一律走「纯 `+` + 单引号包字面量」。** 依据：本项目 `result = '{"code":1,"msg":"…"}';` 已实测可用 ⇒ 表达式编辑器**支持单引号字面量**。

**① 拼 JSON** —— 替换整条表达式，🔴 **注意开头没有 `s"`**：

```
json = json + sep + '{"folderId":"' + hitRow.folderId + '","pathKey":"' + hitRow.pathKey + '","permCateId":' + permCateStr + ',"permType":' + permTypeStr + '}';
```

**② 紧跟其后，另起一个「赋值」组件**（🔴 两版都漏了这行 ⇒ 多条命中粘成 `}{`）：

```
sep = ',';
```

**③ 出参组装**：

```
result = '{"code":0,"employeeId":"' + employeeId + '","identityId":' + Convert<String>(idInt) + ',"scope":"' + scope + '","count":' + Convert<String>(hitCount) + ',"permissions":[' + json + ']}';
```

**读法（三句话）**：
1. 每段**静态文本**用**单引号**包住 —— 如 `'{"folderId":"'`，里面的双引号**原样写、不转义**；
2. **变量**夹在中间用 `+` 连起来；**数值**（`permCateStr` / `idInt` / `hitCount`）**不加引号**；
3. 整个表达式的第一个字符只能是 `json` 或 `'`，**绝不能是 `s"`**。

⛔ **错法对照（09-11 实际发生过）**：

| ❌ 写法 | 错在哪 |
|---|---|
| `s"${json}${sep}'{"folderId":"'${hitRow.folderId}'",…` | ① `s"` 遇第二个 `"` 即结束，后面 `folderId` 成裸标识符 ⇒ 编译不过；② 用 `'` 包值 ⇒ 产出 `'xxx'`，而 **JSON 里必须是 `"xxx"`**；③ 末尾缺 JSON 右花括号 `}` |
| `s"'{"code":0,…' + employeeId + '"…` | `s"` 与 `+` **混在同一条表达式** ⇒ 同样坏 |

> 💡 **退路**：若平台**强制**给出 `s"…"` 骨架（文本组件含插值时的默认形态），改用 **§3.7 方案 B（双引号变量法）** —— 加 `let q: String = '"';`，模板里全部用 `${q}`。⛔ `\"` 转义**不可用**（官方：文本组件「不支持任何转义字符」）。

---

### 3.7 🔴「必须有 `s`」约束下的正解（2026-09-11，官方文档 + 实测）

**官方文档事实**（`codewave-brain`：`20.应用开发/15.逻辑功能实现/40.逻辑组件使用/20.原子项.md` §文本）：

> **「文本」组件** —— 用于文本类型变量赋值，默认值 `""`（空文本），返回 String。
> 使用说明（原文）：② 支持在文本中嵌入有返回值的变量、调用逻辑、调用接口、内置函数等表达式；③ **支持在表达式中通过拖拽快捷操作拼接其他表达式**；⑤ 🔴 **不支持任何转义字符**，例如不能用 `\n` 表示文本换行，直接按回车键换行即可。

⇒ 🔴 **`\"` 这条路被官方文档明确否掉**（文本组件不支持转义字符）。§3.2 / §3.6 里"备选：`s"…"` + `\"` 转义"**作废**。

**但有一条更关键的规律**（本项目实测 + 拖出代码佐证）：

| 文本组件的内容 | 平台导出的 NASL |
|---|---|
| **纯静态**（没有 `${}`） | `'内容'` —— **单引号**，里面的双引号**原样放进去，合法** |
| **含 `${}` 插值** | `s"内容"` —— 🔴 这时若内容里有**裸双引号**，字符串当场提前结束 ⇒ **编译不过** |

**铁证**：拖出代码里的 `result = '{"code":1,"msg":"参数错误：employeeId 为空"}';` —— **没有 `s`**，是单引号包裹，内部双引号原样存在。

⇒ **根因（精确版）**：不是"双引号不能用"，而是 **双引号与 `${}` 塞进同一个文本组件**才出事。**二者拆开就没事。**

---

#### ✅ 方案 B：「必须有 `s`」约束下的正解 —— 让双引号变成变量

思路：`s"…"` 里**一个裸双引号都不出现**，全部用 `${q}` 插进去。

**① 新增局部变量 `q`** —— 用「文本」组件赋值为**一个双引号字符**（内容是单个 `"`，无 `${}` ⇒ 平台导出 `'"'` ✅ 合法）：

```
let q: String = '"';
```

**② 拼 JSON** —— 整条就是一个 `s"…"` 模板，内部零裸双引号：

```
json = s"${json}${sep}{${q}folderId${q}:${q}${hitRow.folderId}${q},${q}pathKey${q}:${q}${hitRow.pathKey}${q},${q}permCateId${q}:${permCateStr},${q}permType${q}:${permTypeStr}}";
```
> 🔴 **注意：开头那个 `{` 与末尾那个 `}` 缺一不可**（本段最初漏写了开头的 `{`，被原样照抄了 6 轮，2026-09-11 第七轮才修）。

**③ 出参组装** —— 同样全程 `${q}`：

```
result = s"{${q}code${q}:0,${q}employeeId${q}:${q}${employeeId}${q},${q}identityId${q}:${Convert<String>(idInt)},${q}scope${q}:${q}${scope}${q},${q}count${q}:${Convert<String>(hitCount)},${q}permissions${q}:[${json}]}";
```
> 🔴 同理：`s"` 后面紧跟的 `{` 与末尾 `]` 之后的 `}` 都是对象边界，**不能省**。

**④ `sep` 的赋值**（无插值 ⇒ 平台导出 `','`）：

```
sep = ',';
```

> ⚠️ 若模板里的**单独 `}`** 报错（个别实现会把它当配对符），同样办法绕：加 `let b: String = '}';`，末尾改写成 `${b}`。
> ⚠️ 数值插值（`${permCateStr}` / `${Convert<String>(idInt)}`）**不要**再包 `q` —— 它们本来就该不带引号。

#### 对照：方案 A（不用 `s`，双引号片段各自独立成组件）

见 §3.6 —— 每段**静态文本**（含双引号）单独放一个文本组件 ⇒ 平台导出 `'…'`，再用 `+` 与变量连。

> 🔴 **方案 A / B 二选一，⛔ 绝不要混在同一条表达式里**（混 = 两版拖出代码失败的根因）。
> **选哪条**：平台若**强制**给你 `s"` 骨架 ⇒ 走 **B**；能自由拆片段 ⇒ 走 **A**。

#### ✅ 历次修正状态（截至**第八轮** 2026-09-11 18:00 —— 🎉 **全部修完，代码已与照抄版逐字一致，可发布**）

**✅ 这版改对的，别动**：`tok` / `permTypeStr` 补了初值；`q` 变量法用对了；**JSON 拼接已全部换成纯 `s"…"` + `${q}`**（方向完全正确，`s"` 与 `+` 混用的病根已除）。

| # | 位置 | 这版写的 | ✅ 应为 | 后果 |
|---|---|---|---|---|
| **P0-1** | 变量声明 | `let sep: String = ',';` | 🔴 `let sep: String = '';` | ✅ **第四轮已修**。`sep` 语义 = 「**本条记录前面要加的分隔符**」，首条必须为空串。初值给 `','` ⇒ 产出 `[,"{…}"]`（**前导逗号**）⇒ **JSON 非法**。⚠️ 只有 `count=0`（无命中）时才看不出来 |
| **P0-2** | ForEach 循环体末尾 | **没有** `sep = ',';` 这一行 | 在 `json = …` 那行**后面**另起一个「赋值」组件：`sep = ',';` | ✅ **第四轮已修**。初值改回 `''` 后，这里若不补 ⇒ 多条命中粘成 `}{` ⇒ **JSON 非法**。⚠️ **只有 1 条命中时完全看不出来** ⇒ 必须用 **≥2 条权限**的工号测 |
| **P0-3** | `json = …` 行末尾 | `…${permTypeStr}";` | `…${permTypeStr}}";` | ✅ **第五轮已修**（补了裸 `}`）。**JSON 对象没闭合** ⇒ 产出 `{"folderId":"3",…,"permType":"10` 缺收尾 `}` ⇒ **JSON 非法** |
| **P0-4** | `json` / `result` 两行**开头** | 模板从 `${json}${sep}${q}folderId…` / `${q}code${q}…` 直接开始 —— **没有开头的 `{`** | 🔴 `json` 行：`${json}${sep}{${q}folderId…`；`result` 行：`s"{${q}code…` | ✅ **第七轮已修**（两行都补上了）。成因是**本文件 §3.7 方案 B 原文漏写 `{`（笔误）**，主人照抄所以继承。产出 `["folderId":"3",…]`（数组里跟冒号）⇒ **JSON 非法**，但**编译照样通过** |
| **P0-5** | `json` 行 `permType` 的值 | `${q}${permTypeStr}}` | `${permTypeStr}}`（删掉值前面那个 `${q}`） | ✅ **第八轮已修**。产出 `…"permType":"10}` —— **引号只开不闭、把对象收尾 `}` 吞进字符串** ⇒ **JSON 非法**（不只是类型问题）。⚠️ 键名两侧的 `${q}` 必须保留。模拟验证：删掉后 **1 条 / 2 条命中均解析通过** |
| P1 | `json` / `result` 行 | `${q}${permCateStr}${q}`、`${q}${Convert<String>(idInt)}${q}` | `${permCateStr}`、`${Convert<String>(idInt)}`（**数值不包 `q`**） | ✅ **第六轮已全部改对**：`permCateId` ✅、`identityId` ✅、`count` ✅ —— 数值一律裸插值，与契约 integer 一致 |

> 🔑 **`sep` 的分工（一行记牢）**：**声明时给 `''`（首条不加逗号），循环末尾给 `','`（从第二条起加）。**
> 四版都在"用一个常量代替自控逗号"上栽过 —— ①② 漏了循环末尾那句，③ 把常量又提前塞进了初值。
> **✅ 第四轮起这一对彻底闭环**：初值 `''` + 循环末尾 `sep = ',';` 两处都对。
>
> 🎉 **第八轮（18:00）：P0-1 ~ P0-5 + P1 全部 ✅，代码与下方照抄版逐字一致。**
> **✅ 第五轮（17:50）**：P0-3 补 `}` 已落地 ⇒ `b` 变量**不需要建**（裸 `}` 直接写）。
> **✅ 第六轮（17:55）**：数值引号那一组（P1）全部改对。
> **✅ 第七轮（18:00）**：P0-4 两行开头的 `{` 都补上了。
> **✅ 第八轮（18:00）**：P0-5 `permType` 值前多余的 `${q}` 删掉 —— **八轮拉锯结束**。
>
> 📌 **八轮纠缠的总账**：根因只有 2 个 —— ① 想用「常量」代替「自控逗号」（P0-1 + P0-2 是一对，必须两处配合）；② JSON 模板里**花括号与引号的成对性**（`{` `}` 各一次、`"` 必须成对、数值不包引号）。剩下全是这两条的变体。
>
> 💡 **收尾 `}` 的两条路**：① **直接写裸 `}`**（已落地）；② 万一报错才加 `let b: String = '}';` 用 `${b}` —— §3.1 已把 `b` 标为**可选**。
> 💡 **开头 `{` 同理**：① 直接写裸 `{`（与 `}` 对称，**优先**）；② 若文本组件/表达式编辑器不肯收裸 `{`，加 `let lb: String = '{';` 用 `${lb}`。
> ⚠️ **`{` 别漏在紧邻位置**：`json` 行要写在 `${json}${sep}` **之后**、`${q}folderId` **之前**；`result` 行要写在 `s"` **之后**、`${q}code` **之前**。两处都只在**对象最外层**出现一次，循环内不要重复加。

#### ✅ 照抄版定稿（**第八轮 = 最终版**，主人当前代码已与此逐字一致）

```nasl
    /* ===== 变量（只列本轮相关的）===== */
    let json: String = '';
    let sep: String = '';        // 🔴 首条不加逗号 ⇒ 初值必须是空串
    let q: String = '"';         // 一个双引号字符（方案 B 专用）
    // let b: String = '}';      // 可选：仅当裸 } 报错时才启用
    // let lb: String = '{';     // 可选：仅当裸 { 报错时才启用

    /* ===== 拼 JSON 的 ForEach 循环体 ===== */
    for (hitRow in hitList, index in 0) {
        hitCount = hitCount + 1;
        permCateStr = Convert<String>(hitRow.permCateId);
        permTypeStr = Convert<String>(hitRow.permType);
        json = s"${json}${sep}{${q}folderId${q}:${q}${hitRow.folderId}${q},${q}pathKey${q}:${q}${hitRow.pathKey}${q},${q}permCateId${q}:${permCateStr},${q}permType${q}:${permTypeStr}}";
        //                        ↑ 开头的 { = JSON 对象起始（第六轮补，只在此处出现一次，循环内不重复）
        //                                                                                              ↑ 末尾 } = JSON 对象收尾（第五轮补）
        sep = ',';               // 🔴 另起一个「赋值」组件，紧跟其后，⛔ 不能省
    }

    /* ===== 出参组装 ===== */
    result = s"{${q}code${q}:0,${q}employeeId${q}:${q}${employeeId}${q},${q}identityId${q}:${Convert<String>(idInt)},${q}scope${q}:${q}${scope}${q},${q}count${q}:${Convert<String>(hitCount)},${q}permissions${q}:[${json}]}";
    //         ↑ 开头的 { = 整个返回对象起始（第六轮补）；末尾 } = 对象收尾
```

> 🎉 **第八轮：无需再改** —— 主人当前代码与上面这段**逐字一致**，模拟渲染 `n=0/1/2/3` 全部产出**合法 JSON**。
>
> ```
> P0-5 的最后一次改动（已完成）：
> 改前：…${q}permType${q}:${q}${permTypeStr}}      → 产出 "permType":"10}  ← 引号只开不闭、把收尾 } 吞进字符串 ⇒ JSON 非法
> 改后：…${q}permType${q}:${permTypeStr}}          → 产出 "permType":10}
> ```
>
> ⚠️ **日后重看这段，记住**：**键名两侧 `${q}` 成对保留，值两侧只在「字符串值」才包 `${q}`，数值一律裸插值**。
> 💡 **裸 `{` / `}` 若编辑器不收**：加 `let lb: String = '{';` / `let b: String = '}';`，把裸符号换成 `${lb}` / `${b}`。**当前平台接受裸写法，不需要建这两个变量**。
>
> ##### 🧪 模拟验证（2026-09-11 18:00，脚本按 NASL 模板语义渲染后喂 JSON 解析器）
>
> | 命中数 n | 产物合法性 |
> |---|---|
> | 0（无权限） | ✅ `count=0, permissions:[]`，**无前导逗号** |
> | 1 | ✅ 合法 |
> | 2 | ✅ 合法，`permissions` 两条之间**恰好一个逗号** |
> | 3 | ✅ 合法 |
>
> ```
> n=2 完整产物：
> {"code":0,"employeeId":"U-03","identityId":1234,"scope":"resident","count":2,
>  "permissions":[{"folderId":"3","pathKey":"学院0","permCateId":9,"permType":10},
>                 {"folderId":"4","pathKey":"学院1","permCateId":9,"permType":10}]}
> ```

**改完后的预期产物**（用有 2 条权限的工号验证）：

```json
{"code":0,"employeeId":"U-03","identityId":1234,"scope":"resident","count":2,"permissions":[{"folderId":"3","pathKey":"xx学院","permCateId":9,"permType":10},{"folderId":"7","pathKey":"yy学院","permCateId":8,"permType":10}]}
```

> 🧪 **本产物已用脚本按模板语义模拟校验**（把 `${…}` 当插值、其余原样输出，再喂给 JSON 解析器）：
> **第六版现状 1 条 / 2 条命中均解析失败**；补 `{` + 删掉多余 `${q}` 后**均解析通过**。
> 自查三点：`[` **紧跟 `{`**（不是逗号）、两条之间**只有一个逗号**、`permCateId` / `permType` 的值**是数字没引号**。

🔴 **自查三处**：① `permissions":[` 里第一个字符**不是逗号**；② 两条记录之间**有且只有一个逗号**；③ 每个 `{` 都有配对的 `}`，`permCateId` / `permType` 的**值是数字、不带引号**。

---

## 四、与另外三个接口的**关键差异**（🔴 对接方必读）

| | 前三个接口 | 本接口 |
|---|---|---|
| 返回体 | **中文文案**（`授权成功：…`） | **JSON 字符串** |
| 判成败 | 前缀匹配 | 解析 JSON 的 `code` |
| 幂等性 | 写操作 | **只读**，随便调 |

> 判读：`code == 0` = 成功（**哪怕 `count == 0` 也是成功，只是"这人没权限"**）；`code != 0` = 失败，看 `msg`。

---

## 五、拖组件蓝图

```
[开始]
  ├─【变量】tok / identityId(List<Integer>) / idInt / scanFolders / permResp / permList
  │        / hitCount=0 / json='' / sep='' / permCateStr='' / permTypeStr='' / hitList(List<HyPermHit>)=[]
  ├─【If】!HasValue(employeeId) → result=参数错误JSON【End】
  ├─【调用逻辑】hyGetToken(undefined) → tok                 ★ 循环外，只此一次
  ├─【调用逻辑】getIdentityIdByAccount(tok, employeeId) → identityId
  ├─【If】!HasValue(identityId) 或 Get(identityId,0)<=0 → result=解析人员失败JSON【End】
  ├─【赋值】idInt = Get(identityId, 0)
  ├─【If】scope == 'all' →【SQL】SELECT * FROM JyglHyFolderMap WHERE isDelete=0 AND level IN (1,2,3,4) → scanFolders
  │   【Else】           →【SQL】SELECT * FROM JyglHyFolderMap WHERE isDelete=0 AND level IN (1,2)     → scanFolders
  ├─【If】!HasValue(scanFolders) → result=目录映射表无数据JSON【End】
  ├─【ForEach】folderRow ∈ scanFolders
  │     ├─【调用接口】LoadFolderPermission(token=tok, folderId=Convert<Integer>(folderRow.folderId)) → permResp
  │     │        ⚠️ IDE 签名里若多出 Content_Type，补一行 = undefined
  │     ├─【If】permResp.result == 0
  │     │     └─【赋值】permList = permResp.data.permissions
  │     │        【ForEach】permRow ∈ permList
  │     │           └─【If】permRow.memberId==idInt 且 permRow.memberType==1 且 permRow.entryId==folderRow.folderId
  │     │                 └─【Add】hitList ← {folderId=folderRow.folderId, pathKey=folderRow.pathKey,
  │     │                                     permCateId=permRow.permCateId, permType=permRow.permType}
  │     └─【Else】空（单个目录查询失败静默跳过）  ← 平台若强制生成"否"分支，留空即可，⛔ 不要填自赋值
  ├─【ForEach】hitRow ∈ hitList → permCateStr/permTypeStr 转字符串、拼 json 串、hitCount+1
  └─ result = 完整 JSON
[结束]
```

> 🔴 **循环内只「调用接口」，不「调用逻辑」**（CodeWave 红线）。所以 `hyGetToken` / `getIdentityIdByAccount` 必须在循环**外**，`LoadFolderPermission` 才在循环内。

### 🔴 拖完必查 10 条（09-10 实测归纳 + 09-11 拖出版三轮实测补漏）

1. **循环变量被平台重命名** —— 拖出来的循环头**默认叫 `item` / `item1` / `Item`**（嵌套循环自动加数字）。若你在表达式里手写了语义名（`folderRow` / `permRow` / `hitRow`）却没同步改循环头，它就成了"声明了但从未赋值"的空壳。
   **症状**：`Convert<Integer>(folderRow.folderId)` 恒 0 → 传 folderId=0 → 801；或 `permRow.entryId == folderRow.folderId` 恒 false → **永远查不到权限**。
   **自查**：全逻辑搜这三个引用点 —— `Convert<Integer>(folderRow.folderId)`、`permRow.entryId == folderRow.folderId`、`hitRow.folderId` —— **必须跟循环头同名**（用平台默认的 `item`/`item1`/`Item` 也行，**只要三处一致**）。
2. **`hitList` 必须初始化 `= []`**（类型 `List<app::structures::HyPermHit>`）。未初始化 → `Add` 无效 → 永远 `count=0`。
3. **判相等按 string、传参按 integer** —— `entryId` 官方类型是 **string**，`folderRow.folderId` 也是 String ⇒ `permRow.entryId == folderRow.folderId` 直接比；⛔ **不要** `Convert<Integer>(permRow.entryId)`。而接口入参 `folderId` 是 integer ⇒ **必须** `Convert<Integer>(folderRow.folderId)`。
4. **列表判空只用 `HasValue`** —— `Length` 是字符串函数，对 `List<结构体>` 传参会报「参数类型不一致」。本文档已全部改为 `HasValue` 单判（官方 `HasValue` 已涵盖空集合）。
5. **`Content_Type` 参数**：GET 无 body，但平台通常仍生成该参数 ⇒ 签名里有就填 `undefined`（= 不发这个头），没有就不管。**本接口不需要任何自定义请求头**（鉴权靠 query 的 `token`）。
6. **JSON 拼接只能走一条路** —— 要么**方案 B**（纯 `s"…"` + `${q}`），要么**方案 A**（`'…'` 片段 + `+`），⛔ 绝不能混在同一条表达式里。混用是 09-11 两版拖出代码"编译不过"的根因，逐行对照见 §3.5 / §3.7。
7. **自增计数器必须给初值** —— `let hitCount: Integer = 0;`。拖出版写成了 `let hitCount: Integer;` ⇒ 首次 `hitCount + 1` 是 `null + 1`。
8. **循环内只「调用接口」，不「调用逻辑」** —— `hyGetToken` / `getIdentityIdByAccount` 必须在循环**外**（C18：循环内禁调服务端逻辑）。⚠️ 但本接口**必然**在循环内调第三方接口 `LoadFolderPermission`，见下方风险说明。
9. 🔴 **`sep` 的初值与赋值是"两处配合"** —— 声明 `let sep: String = '';`（**空串**）+ 循环体**末尾** `sep = ',';`。只做一处就是错的：初值给 `','` ⇒ **首条前多一个逗号**（`[,…`）；循环末尾漏写 ⇒ **多条粘成 `}{`**。⚠️ 前者只有 `count=0` 时看不出、后者只有 **1 条命中**时看不出。
10. 🔴 **每个 JSON 对象都要闭合 `}`，且数值不加引号** —— 收尾 `}` **直接写裸 `}` 即可**（与开头裸 `{` 对称；`b` / `lb` 变量**不需要建** —— ⚠️ 09-11 终稿就是这么落地的。仅当快捷键/编辑器**拒收裸符号**时才退化用 `let lb: String = '{';` / `let b: String = '}';` + `${lb}` / `${b}`，见 §3.1 变量表与 §3.7 P0-3）；`permCateId` / `permType` / `identityId` 的插值**不要**包 `${q}`，否则值变字符串、与契约 **integer** 不符 —— 这两类错都只有**把产物拉出来看**才发现。

> ⚠️ **C40「循环内禁止调用第三方接口」= 本接口的已知架构风险（如实记录）**
> `scope='all'` 时最多上百个目录、串行调用 ⇒ 平台可能限制或开放成 HTTP 后超时。
> **项目已有同类先例**：`revokeAllCollegePerms` 遍历全部 level=4 目录逐个撤 ⇒ 症状「进审批页慢」（`docs/待办清单-鸿翼对接汇总.md` L121），**根因相同**。
> **缓解**：① 默认 `scope='resident'` 只扫 L1+L2（约 10~20 个，秒级）—— 这是默认值存在的意义；② `all` 模式上线前先实测耗时，必要时收窄到"该人所属学院"的 L3/L4。

---

## 六、开放为接口 + 发布

1. 逻辑树右键 `getPersonPermissions` → **开放为接口** → 路径默认 `/rest/getPersonPermissions` → 鉴权 `akSkAuth` → 导出。
2. 🔴 **发布应用**（不发布 = 外调 404 / API 管理页看不到）。改逻辑后也要重发布 + 调用方「更新接口」。
3. 集成中心 → 应用API管理 → 记下**实际地址**与参数位置（method / query / body），把 `ak` / `sk` 交给调用方。
4. ⚠️ **`scope` 必须有默认值 `'resident'`**，否则开放后它变必填 ⇒ "只传工号也能调"就不成立。

---

## 七、调用示例

### curl

```bash
TS=$(date +%s)
SIG=$(printf "%s" "${AK}${SK}${TS}" | md5sum | cut -d' ' -f1)

# 只传工号（默认 scope=resident，秒级）
curl -G "{制品域名}/rest/getPersonPermissions" \
  -H "ak: ${AK}" -H "timestamp: ${TS}" -H "signature: ${SIG}" \
  --data-urlencode "employeeId=41255"

# 连逐课 L4 一起查（慢，慎用）
curl -G "{制品域名}/rest/getPersonPermissions" \
  -H "ak: ${AK}" -H "timestamp: ${TS}" -H "signature: ${SIG}" \
  --data-urlencode "employeeId=41255" \
  --data-urlencode "scope=all"
```

### 在另一 CodeWave 应用里调

集成中心 → 应用API管理 → 建第三方 API 分组 → 录 `{制品域名}/rest/getPersonPermissions` → 加 query 参数 `employeeId` / `scope` → 选 `akSkAuth` → **服务端逻辑**里用「调用接口」组件调（⚠️ 前端逻辑不能挂鉴权方式）→ 拿到 `result` 后 `JSON.parse` 取 `code` / `count` / `permissions`。

---

## 八、排错表

| 现象 | 原因 | 处理 |
|---|---|---|
| 401 | 鉴权头缺 / `signature` 算错 / `timestamp` 过期 | `signature = md5(ak+sk+timestamp)`（32 位小写），时间戳取当前 Unix 秒 |
| 404 | 没开放为接口，或**开放后没发布应用** | 重新开放 + 发布 |
| `code:1 解析人员失败` | 工号在鸿翼无对应人员 | 确认该人已同步进鸿翼组织架构 |
| `code:2 目录映射表无数据` | `JyglHyFolderMap` 查不到 / 数据源没配讲义库 | 查数据源配置 |
| **永远 `count:0`，但鸿翼后台明明有授权** | ① 循环变量改名没改干净（§五 第 1 条）<br>② `hitList` 没初始化（第 2 条）<br>③ 权限是**继承**来的（`entryId != folderId`）→ 本接口**故意不报**，符合预期<br>④ `scope=resident` 但权限在 L4 → 改 `scope=all` | 依次排查 |
| `count` 比预期少 | 继承项不计（设计如此）；`memberType != 1`（非个人授权）不计 | 到鸿翼后台按目录看授权明细核对 |
| `scope=all` 超时 | 目录上百、串行 0.3s/个 | 改回默认 `resident`；查 L4 走定向思路 |

---

## 九、实测清单

> ✅ **前 5 项已于 09-11 完成**（`LoadFolderPermission` 已在分组 ⇒ 无需导入；结构体已建；逻辑已拖完并 8 轮核对；已开放为接口 + 已发布）。🔴 **下面 5 条实测全部未跑** —— 这是当前唯一剩余工作。
>
> ⚠️ 实测②（无权限工号，`count=0`）**查不出逗号问题**，必须至少跑 实测①（≥2 条权限的工号）才算过。

- [x] ~~导入 `swagger_权限查询_导入.json` 到 `jyglqxcx`，能看到 `LoadFolderPermission`~~ → ✅ 无需导入，**已在分组内**（09-11 18:05 核实）
- [x] ~~建 `HyPermHit`（含 `pathKey` 4 字段）~~ → ✅ 已建
- [x] ~~建 `getPersonPermissions`，`scope` 默认值 `'resident'`~~ → ✅ 已拖完
- [x] ~~拖完按 §五 5 条自查（尤其循环变量名 + `hitList` 初始化）~~ → ✅ 8 轮核对通过（§3.7）
- [x] ~~开放为接口 + **发布应用**~~ → ✅ 已开放 + 已发布（09-11 18:10）
- [ ] 实测①：查**已知有授权**的工号（🔴 **须 ≥2 条权限**）→ `count > 0`，`folderId` / `pathKey` 与鸿翼后台一致
- [ ] 实测②：查**无任何授权**的工号 → `count = 0` 且 **`code = 0`**（不是报错）
- [ ] 实测③：查**只有继承权限**的人（如院长靠 L2 继承到 L3）→ `count = 0`，符合预期
- [ ] 实测④：先 `getPersonPermissions` 记下 count → 调 `removePersonPermission` → 再查应 `count = 0`
- [ ] 实测⑤：`scope=all` 在**测试环境**跑一次，确认不超时（生产慎用）

---

**文档结束** · 2026-09-11 · 对应四接口设计文档 §四（接口①）
