require "net/ftp"
require "stringio"

module Storage
  # FTP backend (bonus). Opens a short-lived connection per operation,
  # which keeps it thread-safe under Puma without a connection pool.
  class FtpAdapter < Adapter
    NETWORK_ERRORS = [Net::FTPError, SocketError, Timeout::Error, SystemCallError, IOError, EOFError].freeze

    def self.from_config(options)
      new(
        host: options[:host],
        port: options.fetch(:port, 21).to_i,
        username: options[:username],
        password: options[:password],
        directory: options.fetch(:directory, "/"),
        passive: options.fetch(:passive, true)
      )
    end

    # +connection_factory+ lets tests inject a fake Net::FTP.
    def initialize(host:, username:, password: "", port: 21, directory: "/", passive: true, connection_factory: nil)
      raise ConfigurationError, "FtpAdapter: missing host" if host.to_s.empty?

      @directory = directory.to_s.empty? ? "/" : directory.to_s
      @connection_factory = connection_factory || lambda {
        Net::FTP.new(host, port: port, username: username, password: password.to_s,
                           passive: passive, open_timeout: 5, read_timeout: 30)
      }
    end

    def store(key, data)
      with_connection do |ftp|
        ftp.storbinary("STOR #{key}", StringIO.new(data.b), Net::FTP::DEFAULT_BLOCKSIZE)
      end
      true
    rescue Net::FTPPermError => e
      raise Error, "FTP write failed: #{e.message}"
    end

    def retrieve(key)
      with_connection do |ftp|
        buffer = String.new(encoding: Encoding::BINARY)
        ftp.retrbinary("RETR #{key}", Net::FTP::DEFAULT_BLOCKSIZE) { |chunk| buffer << chunk }
        buffer
      end
    rescue Net::FTPPermError => e
      raise NotFound, "No blob stored for key #{key}" if e.message.start_with?("550")

      raise Error, "FTP read failed: #{e.message}"
    end

    def delete(key)
      with_connection { |ftp| ftp.delete(key) }
      true
    rescue Net::FTPPermError => e
      return true if e.message.start_with?("550")

      raise Error, "FTP delete failed: #{e.message}"
    end

    private

    def with_connection
      ftp = @connection_factory.call
      enter_directory(ftp)
      yield ftp
    rescue Net::FTPPermError
      raise # handled by callers (550 = not found)
    rescue *NETWORK_ERRORS => e
      raise Error, "FTP server error: #{e.class}: #{e.message}"
    ensure
      ftp&.close
    end

    # cd into the storage directory, creating each segment if needed.
    def enter_directory(ftp)
      ftp.chdir("/") if @directory.start_with?("/")
      @directory.split("/").reject(&:empty?).each do |segment|
        begin
          ftp.chdir(segment)
        rescue Net::FTPPermError
          ftp.mkdir(segment)
          ftp.chdir(segment)
        end
      end
    end
  end
end
