-- ============================================================================
-- 授课讲义管理系统 - 增量更新 SQL（MODIFY COLUMN COMMENT）V3.2
-- ----------------------------------------------------------------------------
-- 变更内容：
--   仅修正字段注释（COMMENT），不改字段类型、不改数据、不加索引。
--
-- 背景：jygl_hy_folder_map.level 的注释原写「1应用/2学期/3学院/4课程/5教学班」，
--       与 2026-09-10 鸿翼内网实测口径不符。实测结论：
--         level=1 → 应用（讲义管理根），如 161
--         level=2 → 学院，如 162=经济学院 / 167=文理学院 / 174=计算机学院
--         level=3 → 学年，如 278=2025-2026-1
--         level=4 → 课程，如 296=操作系统课程实践(乙)
--         level=5/6 → 教学班，如 297=葛瀛龙-40383教学班
--       且 L2 的 path_key 存的是【学院名】（非学期）。旧注释会误导后续开发，
--       故同步修正 init SQL + 本增量脚本。
--
-- 适用场景：开发环境（已有表）修正注释；生产环境用 init SQL 全新部署时已含新注释。
--
-- ⚠️⚠️ 重要：
--   本脚本执行在 【CodeWave 应用数据库】（jygl_ 自建表所在库），
--   不是教务库（<内网地址·已脱敏>:6001 只读，禁止写入）！
--   执行前请确认当前连接的库是应用库，可用以下语句核对：
--     SELECT table_schema FROM information_schema.tables
--     WHERE table_name = 'jygl_hy_folder_map';
--
-- ⚠️ 纯注释变更，可安全重复执行（幂等）。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. jygl_hy_folder_map.level —— 层级口径修正
-- ----------------------------------------------------------------------------
ALTER TABLE `jygl_hy_folder_map`
  MODIFY COLUMN `level` INT NULL
  COMMENT '层级：1应用（讲义管理根）/2学院/3学年/4课程/5教学班/6教学班（实测口径：L2=学院 pathKey 存学院名，如 174=计算机学院；L3=学年，如 278=2025-2026-1）';

-- ----------------------------------------------------------------------------
-- 2. jygl_hy_folder_map.path_key —— 拼法说明修正（| 分隔，L2 单层存学院名）
-- ----------------------------------------------------------------------------
ALTER TABLE `jygl_hy_folder_map`
  MODIFY COLUMN `path_key` VARCHAR(512) NOT NULL
  COMMENT '唯一键，全路径用 | 分隔：学院|学年-学期|课程|工号|教学班序号（如 计算机学院|2025-2026-2|J9041002|20191012|1）；L2 单层 pathKey 存学院名';

-- ----------------------------------------------------------------------------
-- 3. jygl_hy_folder_map.teacher_id / class_seq / course_selection_number
--    —— 去掉错位层级编号（原写 L5/L6 与实测层级不符）
-- ----------------------------------------------------------------------------
ALTER TABLE `jygl_hy_folder_map`
  MODIFY COLUMN `teacher_id` VARCHAR(32) NULL
  COMMENT '教师工号（教学班层级，冗余便于按教师直查目录）';

ALTER TABLE `jygl_hy_folder_map`
  MODIFY COLUMN `class_seq` VARCHAR(32) NULL
  COMMENT '教学班序号（从选课号末段提取，如 1/2/3）';

ALTER TABLE `jygl_hy_folder_map`
  MODIFY COLUMN `course_selection_number` VARCHAR(255) NULL
  COMMENT '选课课号（冗余，教学班层级才有）';

-- ----------------------------------------------------------------------------
-- 4. jygl_material_file.hongyi_folder_id —— 去掉错位层级编号（原写 L5 教师工号目录）
-- ----------------------------------------------------------------------------
ALTER TABLE `jygl_material_file`
  MODIFY COLUMN `hongyi_folder_id` VARCHAR(64) NULL
  COMMENT '鸿翼所在文件夹id（= 教学班层级目录，冗余便于直查）';

-- ============================================================================
-- 执行后核对（可选）：
--   SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_COMMENT
--   FROM information_schema.COLUMNS
--   WHERE TABLE_SCHEMA = DATABASE()
--     AND TABLE_NAME IN ('jygl_hy_folder_map','jygl_material_file')
--     AND COLUMN_NAME IN ('level','path_key','teacher_id','class_seq','course_selection_number','hongyi_folder_id');
-- ============================================================================
