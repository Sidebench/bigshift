module BigShift
  describe RedshiftUnloader do
    let :unloader do
      described_class.new(redshift_connection, aws_credentials, options)
    end

    let :redshift_connection do
      double(:redshift_connection)
    end

    let :logger do
      double(:logger, debug: nil, info: nil, warn: nil)
    end

    let :aws_credentials do
      {
        'aws_access_key_id' => 'foo',
        'aws_secret_access_key' => 'bar',
      }
    end

    let :options do
      {
        :logger => logger
      }
    end

    let :column_rows do
      [
        {'column' => 'id', 'type' => 'bigint', 'notnull' => 't'},
        {'column' => 'name', 'type' => 'character varying(100)', 'notnull' => 't'},
        {'column' => 'fax_number', 'type' => 'character varying(100)', 'notnull' => 'f'},
        {'column' => 'year_of_birth', 'type' => 'smallint', 'notnull' => 'f'},
      ]
    end

    before do
      allow(redshift_connection).to receive(:exec)
      allow(redshift_connection).to receive(:exec_params).with(/^SELECT "column", .+ FROM "pg_table_def"/, ['my_table']).and_return(column_rows)
    end

    describe '#unload' do
      let :unload_command do
        ''
      end

      let :unload_options do
        {}
      end

      before do
        allow(redshift_connection).to receive(:exec) do |sql|
          unload_command.replace(sql)
        end
        unloader.unload_to('my_table', 's3://my-bucket/here/', unload_options)
      end

      it 'executes an UNLOAD command' do
        expect(unload_command).to match(/^UNLOAD/)
      end

      it 'unloads to the specified S3 prefix' do
        expect(unload_command).to include(%q<TO 's3://my-bucket/here/'>)
      end

      it 'unloads TSV' do
        expect(unload_command).to include(%q<DELIMITER '\t'>)
      end

      it 'adds the provided credentials to the unload command' do
        expect(unload_command).to include(%q<CREDENTIALS 'aws_access_key_id=foo;aws_secret_access_key=bar'>)
      end

      it 'specifies that a manifest file should be written' do
        expect(unload_command).to include(%q<MANIFEST>)
      end

      it 'explicitly selects all columns from the table' do
        select_list = unload_command[/SELECT (.+) FROM "my_table"/, 1]
        aggregate_failures do
          expect(select_list).to include('"fax_number"')
          expect(select_list).to include('"id"')
          expect(select_list).to include('"name"')
          expect(select_list).to include('"year_of_birth"')
        end
      end

      it 'does not allow overwrites of the destination' do
        expect(unload_command).not_to include(%q<ALLOWOVERWRITE>)
      end

      it 'logs that it unloads' do
        expect(logger).to have_received(:info).with('Unloading Redshift table my_table to s3://my-bucket/here/')
      end

      it 'logs when the unload is complete' do
        expect(logger).to have_received(:info).with('Unload of my_table complete')
      end

      context 'when the :allow_overwrite option is true' do
        let :unload_options do
          super().merge(allow_overwrite: true)
        end

        it 'adds ALLOWOVERWRITE to the unload command' do
          expect(unload_command).to include(%q<ALLOWOVERWRITE>)
        end
      end

      context 'when Redshift datatypes need to be converted' do
        let :column_rows do
          super() << {'column' => 'alive', 'type' => 'boolean', 'notnull' => 't'}
        end

        it 'includes the necessary SQL in the unload command' do
          expect(unload_command).to include(%q<(CASE WHEN "alive" THEN 1 ELSE 0 END)>)
        end
      end

      context 'when the credentials contains "token"' do
        let :aws_credentials do
          super().merge('token' => '123')
        end

        it 'includes the token in the credentials string' do
          expect(unload_command).to include(%q<CREDENTIALS 'aws_access_key_id=foo;aws_secret_access_key=bar;token=123'>)
        end
      end

      context 'when the credentials incldue other keys' do
        let :aws_credentials do
          super().merge('hello' => 'world', 'foo' => 'bar')
        end

        it 'does not include them in the credentials string' do
          expect(unload_command).to include(%q<CREDENTIALS 'aws_access_key_id=foo;aws_secret_access_key=bar'>)
        end
      end
    end
  end
end
