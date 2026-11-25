# Metadata only. The bytes live in whichever storage backend is configured.
class CreateBlobs < ActiveRecord::Migration[7.2]
  def change
    create_table :blobs do |t|
      t.string  :identifier,  null: false, limit: 1024 # the client-supplied "id"
      t.bigint  :size,        null: false
      t.string  :checksum,    null: false, limit: 64   # SHA-256 hex of the raw bytes
      t.string  :backend,     null: false              # local | database | s3 | ftp
      t.string  :storage_key, null: false              # key used inside the backend
      t.timestamps
    end

    add_index :blobs, :identifier, unique: true
  end
end
