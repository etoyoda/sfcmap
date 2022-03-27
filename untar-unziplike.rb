#!/usr/bin/ruby
#
# tar アーカイブから pattern にマッチする名前のファイルを抽出し
# unzip -c 互換のヘッダとともに連結・出力する

require 'tarreader'

pattern = Regexp.new(ARGV.shift)
unless pattern and not ARGV.empty?
  puts "usage: #{$0} pattern tarfile ..."
  exit 16
end

ARGV.each {|arg|
  TarReader.open(arg) {|tar|
    # 末尾改行せず。次は必ず extracting またはファイル終端が来るため。
    STDOUT.write "Archive: #{arg}"
    tar.each_entry {|ent|
      next unless pattern === ent.name
      body = ent.read
      STDOUT.write "\n extracting: #{ent.name}\n"
      STDOUT.write body
    }
  }
}
# 非改行終端の電文を処理しやすくするため必ず改行で終える
STDOUT.write "\n"
