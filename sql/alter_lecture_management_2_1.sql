-- ============================================================================
-- 授课讲义管理系统 - 增量更新 SQL（ALTER）V2.3
-- ----------------------------------------------------------------------------
-- 变更：
--   V2.1 (08-18) 初版：jygl_lecture_group 新增 dim_professional / dim_ideological / dim_content
--   V2.2 (08-18) 修复幂等缺陷：改为逐字段独立判断、独立 ADD（原"一字段卡全部"）
--   V2.3 (08-18) 追加：jygl_material_file 新增 file_url（MVP 本地文件引用，漏设计修复）
--
-- ⚠️⚠️ 重要：
--   本脚本执行在 【CodeWave 应用数据库】（jygl_ 自建表所在库），
--   不是教务库（<内网地址·已脱敏>:6001 只读，禁止写入）！
--   执行前请确认当前连接的库是应用库，可用以下语句核对：
--     SELECT table_schema FROM information_schema.tables
--     WHERE table_name = 'jygl_lecture_group';
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 逐字段独立 ADD（幂等：字段已存在则跳过该字段）
-- ----------------------------------------------------------------------------
-- dim_professional（专业符合性）
SET @c1 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_lecture_group'
    AND COLUMN_NAME = 'dim_professional');
SET @s1 = IF(@c1 = 0,
  'ALTER TABLE `jygl_lecture_group` ADD COLUMN `dim_professional` TINYINT DEFAULT 0 COMMENT ''审核维度-专业符合性：0不通过/1通过（仅课程负责人节点可编辑）'' AFTER `version`',
  'SELECT ''dim_professional 已存在，跳过''');
PREPARE st1 FROM @s1; EXECUTE st1; DEALLOCATE PREPARE st1;

-- dim_ideological（思政符合性）
SET @c2 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_lecture_group'
    AND COLUMN_NAME = 'dim_ideological');
SET @s2 = IF(@c2 = 0,
  'ALTER TABLE `jygl_lecture_group` ADD COLUMN `dim_ideological` TINYINT DEFAULT 0 COMMENT ''审核维度-思政符合性：0不通过/1通过（仅课程负责人节点可编辑）'' AFTER `dim_professional`',
  'SELECT ''dim_ideological 已存在，跳过''');
PREPARE st2 FROM @s2; EXECUTE st2; DEALLOCATE PREPARE st2;

-- dim_content（内容合理性）
SET @c3 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_lecture_group'
    AND COLUMN_NAME = 'dim_content');
SET @s3 = IF(@c3 = 0,
  'ALTER TABLE `jygl_lecture_group` ADD COLUMN `dim_content` TINYINT DEFAULT 0 COMMENT ''审核维度-内容合理性：0不通过/1通过（仅课程负责人节点可编辑）'' AFTER `dim_ideological`',
  'SELECT ''dim_content 已存在，跳过''');
PREPARE st3 FROM @s3; EXECUTE st3; DEALLOCATE PREPARE st3;

-- ----------------------------------------------------------------------------
-- jygl_material_file 新增 file_url（MVP 本地文件引用，V2.3 漏设计修复）
-- ----------------------------------------------------------------------------
SET @c4 = (SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
    AND COLUMN_NAME = 'file_url');
SET @s4 = IF(@c4 = 0,
  'ALTER TABLE `jygl_material_file` ADD COLUMN `file_url` VARCHAR(512) NULL COMMENT ''CodeWave 平台文件引用（文件上传组件返回值，MVP 阶段用；鸿翼接入后可废弃）'' AFTER `round_no`',
  'SELECT ''file_url 已存在，跳过''');
PREPARE st4 FROM @s4; EXECUTE st4; DEALLOCATE PREPARE st4;

-- ----------------------------------------------------------------------------
-- 校验：① jygl_lecture_group 应返回 3 行 dim_*；② jygl_material_file 应返回 file_url
-- ----------------------------------------------------------------------------
SELECT 'jygl_lecture_group' AS tbl, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_lecture_group'
  AND COLUMN_NAME LIKE 'dim\_%'
ORDER BY ORDINAL_POSITION;

SELECT 'jygl_material_file' AS tbl, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, COLUMN_COMMENT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_material_file'
  AND COLUMN_NAME = 'file_url';
