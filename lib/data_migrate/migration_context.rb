module DataMigrate
  class MigrationContext < ActiveRecord::MigrationContext
    def initialize(migrations_paths = "db/data")
      @migrations_paths = migrations_paths || "db/data"
    end

    def up(target_version = nil)
      selected_migrations = if block_given?
                              migrations.select { |m| yield m }
                            else
                              migrations
                            end

      DataMigrator.new(:up, selected_migrations, target_version).migrate
    end

    def down(target_version = nil)
      selected_migrations =
        if block_given?
          migrations.select { |m| yield m }
        else
          migrations
        end

      DataMigrator.new(:down, selected_migrations, target_version).migrate
    end

    def run(direction, target_version)
      DataMigrator.new(direction, migrations, target_version).run
    end

    def current_version
      get_all_versions.max || 0
    rescue ActiveRecord::NoDatabaseError
    end

    def migration_files
      paths = Array(migrations_paths)
      Dir[*paths.flat_map { |path| "#{path}/**/[0-9]*_*.rb" }]
    end

    def migrations_status
      db_list = DataSchemaMigration.normalized_versions

      file_list = migration_files.map do |file|
        version, name, scope = parse_migration_filename(file)
        raise IllegalMigrationNameError.new(file) unless version
        version = ActiveRecord::SchemaMigration.normalize_migration_number(version)
        status = db_list.delete(version) ? "up" : "down"
        [status, version, (name + scope).humanize]
      end.compact

      db_list.map! do |version|
        ["up", version, "********** NO FILE **********"]
      end

      (db_list + file_list).sort_by { |_, version, _| version }
    end

    private

    def get_all_versions
      if DataMigrate::DataSchemaMigration.table_exists?
        DataSchemaMigration.normalized_versions.map(&:to_i)
      else
        []
      end
    end

    def move(direction, steps)
      migrator = DataMigrator.new(direction, migrations)

      if current_version != 0 && !migrator.current_migration
        raise UnknownMigrationVersionError.new(current_version)
      end

      start_index =
        if current_version.zero?
          0
        else
          migrator.migrations.index(migrator.current_migration)
        end

      finish = migrator.migrations[start_index + steps]
      version = finish ? finish.version : 0
      send(direction, version)
    end

  end
end
