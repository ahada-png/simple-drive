require "net/ftp"

# Minimal in-memory imitation of the Net::FTP methods FtpAdapter uses.
class FakeFtp
  attr_reader :files, :dirs, :closed_count

  def initialize
    @files = {}
    @dirs = ["/"]
    @cwd = "/"
    @closed_count = 0
  end

  # Returns a factory suitable for FtpAdapter's connection_factory.
  def factory
    -> { @cwd = "/"; self }
  end

  def chdir(dir)
    target = dir.start_with?("/") ? dir : File.join(@cwd, dir)
    raise Net::FTPPermError, "550 No such directory" unless @dirs.include?(target)

    @cwd = target
  end

  def mkdir(dir)
    @dirs << File.join(@cwd, dir)
  end

  def storbinary(cmd, io, _blocksize)
    @files[path_for(cmd)] = io.read
  end

  def retrbinary(cmd, blocksize)
    data = @files.fetch(path_for(cmd)) { raise Net::FTPPermError, "550 File not found" }
    data.b.each_char.each_slice(blocksize) { |chunk| yield chunk.join }
  end

  def delete(name)
    @files.delete(File.join(@cwd, name)) or raise Net::FTPPermError, "550 File not found"
  end

  def close
    @closed_count += 1
  end

  private

  def path_for(cmd)
    File.join(@cwd, cmd.split(" ", 2).last)
  end
end
