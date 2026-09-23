-- ============================================================================
-- 授课讲义管理系统 - 增量更新 SQL（ALTER）V2.2
-- ----------------------------------------------------------------------------
-- 变更内容：
--   1. jygl_material_file 新增 current_version（当前版本号，展示用）
--   2. jygl_hy_folder_map 新增 class_seq（教学班序号，L6 目录必需）
--
-- 适用场景：开发环境增量更新（生产环境用 init SQL 全新部署）
-- 执行顺序：依赖 V2.1（dim_* 字段 + file_url），需先执行 V2.1
--
-- ⚠️⚠️ 重要：
--   本脚本执行在 【CodeWave 应用数据库】（jygl_ 自建表所在库），
--   不是教务库（<内网地址·已脱敏>:6001 只读，禁止写入）！
--   执行前请确认当前连接的库是应用库，可用以下语句核对：
--     SELECT table_schema FROM information_schema.tables
--     WHERE table_name = 'jygl_lecture_group';
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. jygl_material_file 新增 current_version
-- ----------------------------------------------------------------------------
-- current_version（当前版本号，展示用，格式如 v1/v2/v3）
SET @c1 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
    AND COLUMN_NAME = 'current_version');
SET @s1 = IF(@c1 = 0,
  'ALTER TABLE `jygl_material_file` ADD COLUMN `current_version` VARCHAR(32) DEFAULT ''v1'' COMMENT ''当前版本号（展示用，格式如 v1/v2/v3，重提时从鸿翼查最新版本回写）'' AFTER `round_no`',
  'SELECT ''current_version 已存在，跳过''');
PREPARE st1 FROM @s1; EXECUTE st1; DEALLOCATE PREPARE st1;

-- ----------------------------------------------------------------------------
-- 2. jygl_hy_folder_map 新增 class_seq
-- ----------------------------------------------------------------------------
-- class_seq（教学班序号，L6 层级，从选课号末段提取）
SET @c2 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_hy_folder_map'
    AND COLUMN_NAME = 'class_seq');
SET @s2 = IF(@c2 = 0,
  'ALTER TABLE `jygl_hy_folder_map` ADD COLUMN `class_seq` VARCHAR(32) NULL COMMENT ''教学班序号（L6 层级，从选课号末段提取，如 1/2/3）'' AFTER `course_code`',
  'SELECT ''class_seq 已存在，跳过''');
PREPARE st2 FROM @s2; EXECUTE st2; DEALLOCATE PREPARE st2;

-- ----------------------------------------------------------------------------
-- 校验：① jygl_material_file 应返回 current_version；② jygl_hy_folder_map 应返回 class_seq
-- ----------------------------------------------------------------------------
SELECT 'jygl_material_file' AS tbl, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
  AND COLUMN_NAME = 'current_version';

SELECT 'jygl_hy_folder_map' AS tbl, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_hy_folder_map'
  AND COLUMN_NAME = 'class_seq';

-- ============================================================================
-- 执行完成。校验提示：
--   ① jygl_material_file 应返回 current_version 行
--   ② jygl_hy_folder_map 应返回 class_seq 行
-- ============================================================================
