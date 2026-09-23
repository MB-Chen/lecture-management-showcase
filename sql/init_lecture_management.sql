-- ============================================================================
-- 授课讲义管理系统 - 自建表初始化 SQL（全量 7 张，含历次 alter 增量，全新部署用这一个即可）
-- ----------------------------------------------------------------------------
-- 版本：V3.1（已含 V2.0 组/明细 → V2.1 dim_*/file_url → V2.2 current_version/class_seq
--              → 3_0 hongyi_*/token_cache/perm_config → 3_1 approver_folder 全量列）
-- 生成日期：2026-09-09（对齐 CodeWave 实体：token_cache 审计列用 created_at/updated_at）
-- 覆盖：7 张表 = jygl_lecture_group / _item / _material_file / _hy_folder_map /
--               _hy_token_cache / _hy_perm_config / _approver_folder
-- 表前缀：jygl（CodeWave 应用标识）
-- 设计模式：课程组 + 选课号明细双层模型
--   申请组（jygl_lecture_group）= 流程 2.0 承载实体，1 门课 = 1 次提交 = 1 条审批流
--   明细（jygl_lecture_group_item）= 数据真实颗粒度，逐条落库
--
-- ⚠️ 命名铁律：audit 时间列名随表而定——
--     CodeWave 实体认 _at 的表（jygl_hy_token_cache）用 created_at/updated_at；
--     其余表统一 created_time/updated_time。改 CodeWave 实体/建库前先对齐，勿混用。
--     另：本脚本 = DROP + CREATE 全重建，已有数据环境勿直接重跑（会清空表数据）。
--
-- 执行顺序（有外键语义依赖，按序执行）：
--   1. jygl_lecture_group        （组主表，流程绑定实体）
--   2. jygl_lecture_group_item   （组明细，依赖 group.id）
--   3. jygl_material_file        （文件表，依赖 group.id / 可选 item.id）
--   4. jygl_hy_folder_map        （鸿翼目录映射，运行期支撑表）
--   5. jygl_hy_token_cache       （鸿翼 token 缓存，CodeWave 实体认 created_at/updated_at）
--   6. jygl_hy_perm_config       （鸿翼授权状态持久化）
--   7. jygl_approver_folder      （审批人授权账本，V3.1）
--
-- 说明：CodeWave 自动建表时可不建外键约束（实体关联驱动），
--       此处按 DDL 定稿仅建索引；如需外键可自行补充。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 表 1：jygl_lecture_group（申请组主表，流程 2.0 绑定实体）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_lecture_group`;
CREATE TABLE `jygl_lecture_group` (
  -- ═══ 系统字段 ═══
  `id`                  BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `created_by`          VARCHAR(255) NULL     COMMENT '创建人（CodeWave userId=employee_id）',
  `created_time`        DATETIME     NULL     COMMENT '创建时间',
  `updated_by`          VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`        DATETIME     NULL     COMMENT '修改时间',
  `is_delete`           TINYINT      DEFAULT 0 COMMENT '删除标识',

  -- ═══ 从教务抄来的冗余字段（提交时一次填入，列表直接查）═══
  `academic_year`       VARCHAR(255) NULL     COMMENT '学年 ← csm_teaching_task.academic_year',
  `semester`            INT          NULL     COMMENT '学期 ← csm_teaching_task.semester',
  `course_code`         VARCHAR(255) NULL     COMMENT '课程代码 ← csm_teaching_task.course_code',
  `course_name`         VARCHAR(255) NULL     COMMENT '课程名称 ← tpm_course_table.course_cnname',
  `teaching_college`    INT          NULL     COMMENT '开课学院 ← csm_teaching_task.teaching_college（学院角色过滤 + 教秘/教学院长审批人查询入参）',
  `leader_id`           VARCHAR(32)  NULL     COMMENT '课程负责人工号 ← tpm_approval_set.task_user3（负责人过滤用）',
  `leader_name`         VARCHAR(255) NULL     COMMENT '课程负责人userName（格式"工号:姓名"如 20241003:张三，流程2.0审批人变量 leaderName，发起流程时带入）',
  `teacher_id`          VARCHAR(32)  NULL     COMMENT '提交教师工号（登录人 employee_id）',
  `teacher_name`        VARCHAR(255) NULL     COMMENT '提交教师姓名 ← sys_teacher_info.employee_name',

  -- ═══ 讲义内容（用户填写）═══
  `title`               VARCHAR(255) NULL     COMMENT '讲义标题',
  `description`         TEXT         NULL     COMMENT '讲义说明',
  `version`             VARCHAR(32)  DEFAULT 'v1' COMMENT '版本号（展示="v"+round_no，重提+1）',

  -- ═══ 审核维度（2026-08-18 新增，课程负责人节点勾选，硬编码 3 个）═══
  `dim_professional`    TINYINT      DEFAULT 0 COMMENT '审核维度-专业符合性：0不通过/1通过（仅课程负责人节点可编辑）',
  `dim_ideological`     TINYINT      DEFAULT 0 COMMENT '审核维度-思政符合性：0不通过/1通过（仅课程负责人节点可编辑）',
  `dim_content`         TINYINT      DEFAULT 0 COMMENT '审核维度-内容合理性：0不通过/1通过（仅课程负责人节点可编辑）',

  -- ═══ 审批字段（流程 2.0 联动）═══
  `process_id`          VARCHAR(64)  NULL     COMMENT '流程实例ID（流程2.0发起后回写，重提不变）',
  `task_id`             VARCHAR(100) NULL     COMMENT '流程任务ID（流程2.0当前任务实例ID，教师撤回用）',
  `audit_status`        INT          DEFAULT 0 COMMENT '业务状态：0待课程负责人审核/1待教学秘书审核/2待教务处处长审核/3待教学院长审批/4已通过/5已驳回',
  `cur_approver`        VARCHAR(4000) NULL    COMMENT '当前审批人userName(逗号分隔多候选人)，与登录人比对控制可见性（待办以流程引擎为准）',
  `reject_reason`       VARCHAR(500) NULL     COMMENT '最近驳回原因（教师重提页显示）',
  `round_no`            INT          DEFAULT 1 COMMENT '提交轮次（驳回重提+1，拆组时原组round_no+1）',
  `item_count`          INT          DEFAULT 0 COMMENT '组内选课号数（冗余，列表展示用）',
  `archiver_name`       VARCHAR(255) NULL     COMMENT '归档人 = 终节点（教学院长）通过人姓名（流程事件回写）',

  -- ═══ 撤回字段（2026-08-17 确认保留，标记位不占状态）═══
  `is_withdrawn`        TINYINT      DEFAULT 0 COMMENT '是否已撤回：0否/1是（撤回标记，不占audit_status、不增轮次）',
  `withdraw_by`         VARCHAR(32)  NULL     COMMENT '撤回人（= teacher_id，教师主动撤回）',
  `withdraw_time`       DATETIME     NULL     COMMENT '撤回时间',

  PRIMARY KEY (`id`),
  INDEX `idx_teacher` (`teacher_id`, `audit_status`, `is_delete`),
  INDEX `idx_leader` (`leader_id`, `audit_status`, `is_delete`),
  INDEX `idx_college` (`teaching_college`, `audit_status`, `is_delete`),
  INDEX `idx_cur_approver` (`cur_approver`(255), `audit_status`),
  INDEX `idx_process` (`process_id`),
  INDEX `idx_semester` (`academic_year`, `semester`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '讲义申请组主表（流程2.0绑定实体）';

-- ----------------------------------------------------------------------------
-- 表 2：jygl_lecture_group_item（组-选课号明细表，数据真实颗粒度）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_lecture_group_item`;
CREATE TABLE `jygl_lecture_group_item` (
  `id`                      BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `group_id`                BIGINT       NOT NULL COMMENT '所属组 jygl_lecture_group.id',
  `course_selection_number` VARCHAR(255) NULL     COMMENT '选课号=教学班唯一标识 ← csm_teaching_task',
  `class_code_list`         VARCHAR(1024) NULL    COMMENT '行政班列表(逗号分隔) ← csm_teaching_task.class_code_list',
  `is_unsubmit`             TINYINT      DEFAULT 0 COMMENT '是否无需提交：0否/1是（教秘维护，标记后教师端该选课号任务消失、可撤销）',
  `is_invalid`              TINYINT      DEFAULT 0 COMMENT '选课号已被教务软删标记（csm_teaching_task.is_delete=1 后置1，仅展示用，不参与统计）',
  `item_status`             INT          DEFAULT 0 COMMENT '明细状态（跟随组流转逐条落库；拆组后独立流转，取值同组级 audit_status）',
  `round_no`                INT          DEFAULT 1 COMMENT '明细轮次（默认随组；拆组后独立递增）',
  `split_group_id`          BIGINT       NULL     COMMENT '可空；该明细拆组后指向新组 id（拆组留痕）',
  `created_by`              VARCHAR(255) NULL     COMMENT '创建人',
  `created_time`            DATETIME     NULL     COMMENT '创建时间',
  `updated_by`              VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`            DATETIME     NULL     COMMENT '修改时间',
  `is_delete`               TINYINT      DEFAULT 0 COMMENT '删除标识',

  PRIMARY KEY (`id`),
  INDEX `idx_group` (`group_id`, `is_delete`),
  INDEX `idx_csn` (`course_selection_number`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '讲义申请组-选课号明细表';

-- ----------------------------------------------------------------------------
-- 表 3：jygl_material_file（讲义文件表，两级关联）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_material_file`;
CREATE TABLE `jygl_material_file` (
  `id`                BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `group_id`          BIGINT       NOT NULL COMMENT '关联组 jygl_lecture_group.id',
  `item_id`           BIGINT       NULL     COMMENT '可空：空=课程级共享文件（组内全部选课号默认生效）；非空=该选课号专属文件（覆盖共享，仅该明细生效）',
  `file_name`         VARCHAR(256) NOT NULL COMMENT '原始文件名',
  `file_ext`          VARCHAR(64)  NULL     COMMENT '扩展名',
  `file_size`         BIGINT       DEFAULT 0 COMMENT '文件大小(字节)',
  `round_no`          INT          DEFAULT 1 COMMENT '提交轮次（区分历史版本）',
  `current_version`   VARCHAR(32)  DEFAULT 'v1' COMMENT '当前版本号（展示用，格式如 v1/v2/v3，重提时从鸿翼查最新版本回写）',
  `file_url`          VARCHAR(512) NULL     COMMENT 'CodeWave 平台文件引用（文件上传组件返回值，MVP 阶段用；鸿翼接入后可废弃）',
  `hongyi_file_id`    VARCHAR(64)  NULL     COMMENT '鸿翼fileId（上传接口返回，必填）',
  `hongyi_ver_id`     VARCHAR(64)  NULL     COMMENT '鸿翼版本ID（PublishFileVersion返回，重提时UPDATE+fileId+majorUpgrade用）',
  `hongyi_folder_id`  VARCHAR(64)  NULL     COMMENT '鸿翼所在文件夹id（= 教学班层级目录，冗余便于直查）',
  `hongyi_file_guid`  VARCHAR(64)  NULL     COMMENT '鸿翼文件GUID（预览URL fileid 用，上传成功后反查回写）',
  `created_by`        VARCHAR(255) NULL     COMMENT '上传人（employee_id）',
  `created_time`      DATETIME     NULL     COMMENT '上传时间',
  `updated_by`        VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`      DATETIME     NULL     COMMENT '修改时间',
  `is_delete`         TINYINT      DEFAULT 0 COMMENT '删除标识（软删留痕，鸿翼侧走回收站）',

  PRIMARY KEY (`id`),
  INDEX `idx_group` (`group_id`, `is_delete`),
  INDEX `idx_item` (`item_id`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '讲义文件表（多文件/多版本/两级上传）';

-- ----------------------------------------------------------------------------
-- 表 4：jygl_hy_folder_map（鸿翼目录映射表，运行期支撑表）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_hy_folder_map`;
CREATE TABLE `jygl_hy_folder_map` (
  `id`                      BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `level`                   INT          NULL     COMMENT '层级：1应用（讲义管理根）/2学院/3学年/4课程/5教学班/6教学班（实测口径：L2=学院 pathKey 存学院名，如 174=计算机学院；L3=学年，如 278=2025-2026-1）',
  `path_key`                VARCHAR(512) NOT NULL COMMENT '唯一键，全路径用 | 分隔：学院|学年-学期|课程|工号|教学班序号（如 计算机学院|2025-2026-2|J9041002|20191012|1）；L2 单层 pathKey 存学院名',
  `semester`                VARCHAR(255) NULL     COMMENT '学期（冗余，便于按学期批量查）',
  `college_id`              INT          NULL     COMMENT '开课学院id（冗余）',
  `course_code`             VARCHAR(255) NULL     COMMENT '课程代码（冗余）',
  `teacher_id`              VARCHAR(32)  NULL     COMMENT '教师工号（教学班层级，冗余便于按教师直查目录）',
  `class_seq`               VARCHAR(32)  NULL     COMMENT '教学班序号（从选课号末段提取，如 1/2/3）',
  `course_selection_number` VARCHAR(255) NULL     COMMENT '选课课号（冗余，教学班层级才有）',
  `folder_id`               VARCHAR(64)  NULL     COMMENT '鸿翼文件夹id（CreateFolder 返回）',
  `parent_folder_id`        VARCHAR(64)  NULL     COMMENT '鸿翼父文件夹id',
  `created_by`              VARCHAR(255) NULL     COMMENT '创建人',
  `created_time`            DATETIME     NULL     COMMENT '创建时间',
  `updated_by`              VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`            DATETIME     NULL     COMMENT '修改时间',
  `is_delete`               TINYINT      DEFAULT 0 COMMENT '删除标识',

  PRIMARY KEY (`id`),
  UNIQUE INDEX `idx_path_key` (`path_key`),
  INDEX `idx_semester` (`semester`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '鸿翼目录映射表（运行期上传必需，非同步表）';

-- ----------------------------------------------------------------------------
-- 表 5：jygl_hy_token_cache（鸿翼token缓存，按需获取24h有效）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_hy_token_cache`;
CREATE TABLE `jygl_hy_token_cache` (
  `id`           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `login_name`   VARCHAR(32)  NOT NULL COMMENT '登录名（工号，唯一）',
  `user_type`    INT          NOT NULL DEFAULT 1 COMMENT '用户类型：1教师/2admin',
  `token`        VARCHAR(512) NULL     COMMENT '鸿翼access_token',
  `fetched_at`   DATETIME     NULL     COMMENT 'token获取时间',
  `last_error`   VARCHAR(512) NULL     COMMENT '最近一次获取失败的错误信息',
  `created_by`   VARCHAR(255) NULL     COMMENT '创建人',
  `created_at`   DATETIME     NULL     COMMENT '创建时间',
  `updated_by`   VARCHAR(255) NULL     COMMENT '修改人',
  `updated_at`   DATETIME     NULL     COMMENT '更新时间',
  `is_delete`    TINYINT      DEFAULT 0 COMMENT '删除标识',

  PRIMARY KEY (`id`),
  UNIQUE INDEX `idx_login_name` (`login_name`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '鸿翼token缓存（24h有效，按需获取）';

-- ----------------------------------------------------------------------------
-- 表 6：jygl_hy_perm_config（鸿翼权限配置，P8页面维护）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_hy_perm_config`;
CREATE TABLE `jygl_hy_perm_config` (
  `id`                BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `scope_type`        INT          NOT NULL COMMENT '授权范围：1教务处/2学院教秘/3学院教学院长/4全体教师组/5课程负责人',
  `college_id`        INT          NULL     COMMENT '学院ID（scope_type=2/3时必填）',
  `course_code`       VARCHAR(255) NULL     COMMENT '课程代码（scope_type=5时必填，负责人随建随授）',
  `semester`          VARCHAR(255) NULL     COMMENT '学期（scope_type=5时必填）',
  `member_type`       INT          NOT NULL COMMENT '成员类型：1用户/2部门/4职位/8用户组',
  `member_id`         VARCHAR(64)  NOT NULL COMMENT '成员ID（identityId，鸿翼侧）',
  `target_folder_id`  VARCHAR(64)  NULL     COMMENT '授权目标文件夹ID',
  `perm_cate_id`      VARCHAR(64)  NULL     COMMENT '权限类别ID（鸿翼侧）',
  `grant_status`      INT          DEFAULT 0 COMMENT '授权状态：0未授/1已授/2失败',
  `last_grant_time`   DATETIME     NULL     COMMENT '最近授权时间',
  `fail_reason`       VARCHAR(512) NULL     COMMENT '授权失败原因',
  `created_by`        VARCHAR(255) NULL     COMMENT '创建人',
  `created_time`      DATETIME     NULL     COMMENT '创建时间',
  `updated_by`        VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`      DATETIME     NULL     COMMENT '更新时间',
  `is_delete`         TINYINT      DEFAULT 0 COMMENT '删除标识',

  PRIMARY KEY (`id`),
  INDEX `idx_scope` (`scope_type`, `college_id`, `is_delete`),
  INDEX `idx_member` (`member_id`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '鸿翼权限配置表（P8页面维护，授权状态总览）';

-- ----------------------------------------------------------------------------
-- 表 7：jygl_approver_folder（审批人授权账本：记录"某人被授到哪门课程的L4目录"）
--        用途：撤旧只撤该人历史授过、且非当前课的目录（替代遍历全部level=4），
--              撤旧请求量与全系统课程总量脱钩，处长跨学院也安全（按identity_id记）。
--        维护方：grantApproverPermission（授成功后 upsert；撤旧/授当前时清理）
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS `jygl_approver_folder`;
CREATE TABLE `jygl_approver_folder` (
  `id`            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `identity_id`   BIGINT       NOT NULL COMMENT '审批人鸿翼 identityId（授到 L4 目录的人）',
  `employee_id`   VARCHAR(32)  NULL     COMMENT '审批人工号（溯源冗余）',
  `folder_id`     VARCHAR(64)  NOT NULL COMMENT '已授的鸿翼课程目录 folderId（L4）',
  `course_code`   VARCHAR(64)  NOT NULL COMMENT '课程代码（用于判断是否当前授的课）',
  `course_name`   VARCHAR(255) NULL     COMMENT '课程名（溯源冗余，可空）',
  `college_name`  VARCHAR(255) NULL     COMMENT '开课学院（溯源冗余，可空）',
  `academic_year` VARCHAR(32)  NULL     COMMENT '学年（如 2026-2027）',
  `semester`      INT          NULL     COMMENT '学期（1/2）',
  `grant_time`    DATETIME     NULL     COMMENT '最近授权时间（授当前课程时刷新）',
  `created_by`    VARCHAR(255) NULL     COMMENT '创建人',
  `created_time`  DATETIME     NULL     COMMENT '创建时间',
  `updated_by`    VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`  DATETIME     NULL     COMMENT '更新时间',
  `is_delete`     TINYINT      DEFAULT 0 COMMENT '删除标识',

  PRIMARY KEY (`id`),
  UNIQUE INDEX `idx_identity_folder` (`identity_id`, `folder_id`),
  INDEX `idx_identity` (`identity_id`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '审批人授权账本（撤旧只撤该人历史授过的课程目录，防权限累积）';

-- ============================================================================
-- 初始化完成。校验提示：
--   SELECT table_name, table_comment FROM information_schema.tables
--   WHERE table_schema = DATABASE() AND table_name LIKE 'jygl_%';
-- ============================================================================
