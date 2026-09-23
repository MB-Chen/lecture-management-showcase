-- ============================================================================
-- 授课讲义管理系统 - 增量更新 SQL（ALTER + CREATE）V3.0
-- ----------------------------------------------------------------------------
-- 变更内容：
--   1. jygl_material_file 新增 hongyi_file_guid（预览 URL 用 GUID，必需）
--   2. jygl_material_file 新增 hongyi_ver_id（版本历史查询用）
--   3. jygl_hy_folder_map 新增 teacher_id（L5 目录关联教师）
--   4. 新建 jygl_hy_token_cache（教师 token 24h 缓存）
--   5. 新建 jygl_hy_perm_config（P8 权限授权状态持久化）
--
-- 适用场景：开发环境增量更新（生产环境用 init SQL 全新部署）
-- 执行顺序：依赖 V2.2（current_version + class_seq），需先执行 V2.2
--
-- ⚠️⚠️ 重要：
--   本脚本执行在 【CodeWave 应用数据库】（jygl_ 自建表所在库），
--   不是教务库（<内网地址·已脱敏>:6001 只读，禁止写入）！
--   执行前请确认当前连接的库是应用库，可用以下语句核对：
--     SELECT table_schema FROM information_schema.tables
--     WHERE table_name = 'jygl_lecture_group';
-- ============================================================================

-- ============================================================================
-- 1. jygl_material_file 新增 hongyi_file_guid（预览 URL 必需）
-- ============================================================================
-- hongyi_file_guid：鸿翼文件 GUID（预览 URL 拼接用，不是数字 FileId）
-- 预览 URL 格式：http://<内网地址·已脱敏>:30179/indrive?ctl=1#/preview?fileid={fileGuid}
-- fileGuid 通过 GetFolderChildren 列目录拿 filesInfo.fileGuid 获取
SET @c1 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
    AND COLUMN_NAME = 'hongyi_file_guid');
SET @s1 = IF(@c1 = 0,
  'ALTER TABLE `jygl_material_file` ADD COLUMN `hongyi_file_guid` VARCHAR(64) NULL COMMENT ''鸿翼文件GUID（预览URL拼接用，非数字FileId，GetFolderChildren返回）'' AFTER `hongyi_file_id`',
  'SELECT ''hongyi_file_guid 已存在，跳过''');
PREPARE st1 FROM @s1; EXECUTE st1; DEALLOCATE PREPARE st1;

-- ============================================================================
-- 2. jygl_material_file 新增 hongyi_ver_id（版本历史查询用）
-- ============================================================================
-- hongyi_ver_id：鸿翼文件版本 ID（GetFileVersionListByFileId 查询版本历史）
-- 虽然 08-21 拍板"不加"，但 Kimi 建议必做（版本历史/重提升级用）——用户确认加上
SET @c2 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
    AND COLUMN_NAME = 'hongyi_ver_id');
SET @s2 = IF(@c2 = 0,
  'ALTER TABLE `jygl_material_file` ADD COLUMN `hongyi_ver_id` VARCHAR(64) NULL COMMENT ''鸿翼文件版本ID（版本历史查询/重提升级用）'' AFTER `hongyi_file_guid`',
  'SELECT ''hongyi_ver_id 已存在，跳过''');
PREPARE st2 FROM @s2; EXECUTE st2; DEALLOCATE PREPARE st2;

-- ============================================================================
-- 3. jygl_hy_folder_map 新增 teacher_id（L5 目录关联教师工号）
-- ============================================================================
-- teacher_id：教师工号（冗余字段，便于直查 L5 目录所属教师）
-- 虽然 pathKey 含工号段可推导，但用户确认加上以减少 JOIN
SET @c3 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_hy_folder_map'
    AND COLUMN_NAME = 'teacher_id');
SET @s3 = IF(@c3 = 0,
  'ALTER TABLE `jygl_hy_folder_map` ADD COLUMN `teacher_id` VARCHAR(32) NULL COMMENT ''教师工号（L5目录所属教师，冗余字段）'' AFTER `course_code`',
  'SELECT ''teacher_id 已存在，跳过''');
PREPARE st3 FROM @s3; EXECUTE st3; DEALLOCATE PREPARE st3;

-- ============================================================================
-- 4. 新建 jygl_hy_token_cache（教师 token 24h 缓存）
-- ============================================================================
-- 登录讲义系统时按工号调集成登录换 token，缓存到此表（约 24h 有效期）
-- 过期重新换取；失败记录 lastError
CREATE TABLE IF NOT EXISTS `jygl_hy_token_cache` (
  `id`          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `login_name`  VARCHAR(32)  NOT NULL COMMENT '工号或admin登录名（唯一键）',
  `user_type`   INT          NOT NULL COMMENT '1=教师/2=admin',
  `token`       VARCHAR(512) NOT NULL COMMENT '鸿翼 token',
  `fetched_at`  DATETIME     NOT NULL COMMENT 'token 换取时间',
  `last_error`  VARCHAR(500) NULL     COMMENT '最近一次获取失败原因（成功时清空）',
  `created_by`  VARCHAR(255) NULL     COMMENT '创建人',
  `updated_by`  VARCHAR(255) NULL     COMMENT '修改人',
  `created_at`  DATETIME     NULL     COMMENT '创建时间',
  `updated_at`  DATETIME     NULL     COMMENT '修改时间',
  `is_delete`   TINYINT      DEFAULT 0 COMMENT '删除标识',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `idx_login_name` (`login_name`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '鸿翼token缓存表（教师集成登录token，24h有效期）';

-- ============================================================================
-- 5. 新建 jygl_hy_perm_config（P8 权限授权状态持久化）
-- ============================================================================
-- P8 权限配置页：记录每条授权的状态（未授/已授/失败），支持重试/校验/撤旧授新
-- scope_type 区分授权对象类型（教务处/学院教秘/学院教学院长/全体教师组/课程负责人）
CREATE TABLE IF NOT EXISTS `jygl_hy_perm_config` (
  `id`               BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `scope_type`       INT          NOT NULL COMMENT '1=教务处/2=学院教秘/3=学院教学院长/4=全体教师组/5=课程负责人',
  `college_id`       INT          NULL     COMMENT '学院ID（scopeType=2/3时，对应 teaching_college）',
  `course_code`      VARCHAR(255) NULL     COMMENT '课程代码（scopeType=5时，课程负责人关联）',
  `semester`         VARCHAR(255) NULL     COMMENT '学期（scopeType=5时，负责人按学期授权）',
  `member_type`      INT          NOT NULL COMMENT '1=用户/2=部门/4=职位/8=用户组（AddFolderPermission memberType）',
  `member_id`        INT          NOT NULL COMMENT 'identityId（int，授权接口 memberId）',
  `target_folder_id` VARCHAR(64)  NULL     COMMENT '授权目标鸿翼文件夹ID',
  `perm_cate_id`     INT          NULL     COMMENT '权限类别ID（cateId，如查看=8/上传新建=17）',
  `grant_status`     INT          DEFAULT 0 COMMENT '0=未授/1=已授/2=失败（授权失败标红用）',
  `last_grant_time`  DATETIME     NULL     COMMENT '最后授权时间（重试成功时更新）',
  `fail_reason`      VARCHAR(500) NULL     COMMENT '授权失败原因（grant_status=2时记录）',
  `created_by`       VARCHAR(255) NULL     COMMENT '创建人',
  `updated_by`       VARCHAR(255) NULL     COMMENT '修改人',
  `created_at`       DATETIME     NULL     COMMENT '创建时间',
  `updated_at`       DATETIME     NULL     COMMENT '修改时间',
  `is_delete`        TINYINT      DEFAULT 0 COMMENT '删除标识',
  PRIMARY KEY (`id`),
  INDEX `idx_scope` (`scope_type`, `college_id`, `course_code`, `semester`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = 'P8权限授权状态持久化表（支持初始化/重试/校验/撤旧授新）';

-- ============================================================================
-- 校验：ALTER 字段 + CREATE 表
-- ============================================================================

-- 1. jygl_material_file 新增字段
SELECT 'jygl_material_file' AS tbl, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
  AND COLUMN_NAME IN ('hongyi_file_guid', 'hongyi_ver_id', 'current_version')
ORDER BY ORDINAL_POSITION;

-- 2. jygl_hy_folder_map 新增字段
SELECT 'jygl_hy_folder_map' AS tbl, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_hy_folder_map'
  AND COLUMN_NAME IN ('teacher_id', 'class_seq')
ORDER BY ORDINAL_POSITION;

-- 3. 新表结构
SELECT 'jygl_hy_token_cache' AS tbl, COUNT(*) AS column_count
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_hy_token_cache';

SELECT 'jygl_hy_perm_config' AS tbl, COUNT(*) AS column_count
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_hy_perm_config';

-- ============================================================================
-- 执行完成。校验提示：
--   ① jygl_material_file 应返回 3 行：hongyi_file_guid / hongyi_ver_id / current_version
--   ② jygl_hy_folder_map 应返回 2 行：teacher_id / class_seq
--   ③ jygl_hy_token_cache 应返回 column_count=11
--   ④ jygl_hy_perm_config 应返回 column_count=17
-- ============================================================================
