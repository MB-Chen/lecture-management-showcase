-- ============================================================================
-- 授课讲义管理系统 - 增量更新 SQL（ALTER）V2.2 - 简化版
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
-- 先检查表是否存在
-- ----------------------------------------------------------------------------
SELECT '检查表是否存在' AS step;
SELECT TABLE_NAME FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('jygl_material_file', 'jygl_hy_folder_map');

-- ----------------------------------------------------------------------------
-- 1. jygl_material_file 新增 current_version
-- ----------------------------------------------------------------------------
-- 先检查字段是否已存在
SELECT '检查 current_version 字段' AS step;
SELECT COUNT(*) AS column_exists
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'jygl_material_file'
  AND COLUMN_NAME = 'current_version';

-- 如果字段不存在则添加（手动执行以下语句）
-- ALTER TABLE `jygl_material_file`
-- ADD COLUMN `current_version` VARCHAR(32) DEFAULT 'v1'
-- COMMENT '当前版本号（展示用，格式如 v1/v2/v3，重提时从鸿翼查最新版本回写）'
-- AFTER `round_no`;

-- ----------------------------------------------------------------------------
-- 2. jygl_hy_folder_map 新增 class_seq
-- ----------------------------------------------------------------------------
-- 先检查字段是否已存在
SELECT '检查 class_seq 字段' AS step;
SELECT COUNT(*) AS column_exists
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'jygl_hy_folder_map'
  AND COLUMN_NAME = 'class_seq';

-- 如果字段不存在则添加（手动执行以下语句）
-- ALTER TABLE `jygl_hy_folder_map`
-- ADD COLUMN `class_seq` VARCHAR(32) NULL
-- COMMENT '教学班序号（L6 层级，从选课号末段提取，如 1/2/3）'
-- AFTER `course_code`;

-- ----------------------------------------------------------------------------
-- 校验：执行完成后检查字段是否添加成功
-- ----------------------------------------------------------------------------
SELECT '校验 jygl_material_file 字段' AS step;
SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'jygl_material_file'
  AND COLUMN_NAME = 'current_version';

SELECT '校验 jygl_hy_folder_map 字段' AS step;
SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'jygl_hy_folder_map'
  AND COLUMN_NAME = 'class_seq';

-- ============================================================================
-- 使用说明：
--   1. 先执行本 SQL 查看检查结果
--   2. 如果字段不存在，取消注释对应的 ALTER TABLE 语句并执行
--   3. 再次执行本 SQL 验证字段是否添加成功
-- ============================================================================
