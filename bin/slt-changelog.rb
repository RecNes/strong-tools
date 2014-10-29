#!/usr/bin/env ruby

require 'optparse'
require 'pathname'

class GitRepo
  def initialize(repo='.')
    @repo = repo
    @sha1 = Hash.new do |cache, ref|
      cache[ref] = `#{git} rev-list -n 1 #{ref}`.strip
    end
  end

  def changelog(next_release=false)
    # --full-history: include individual commits from merged branches
    # --date-order: order commits by date, not topological order
    base = "#{git} log --full-history --date-order --pretty='format:%s (%an)'"
    releases = []
    tags = `#{git} tag`.strip.lines.map(&:strip)
    return '' if tags.empty?
    release_heading = `#{git} log --date=short --format="%ad" -n1 '#{tags.first}'`.strip + ", Version #{clean_version(tags.first)}"
    release = []
    release << " * First release!"
    release << "#{release_heading}\n#{'='*release_heading.length}\n"
    releases << release.reverse.join("\n")
    tags.each_cons(2) do |a,b|
      release_heading = `#{git} log --date=short --format="%ad" -n1 '#{b}'`.strip + ", Version #{clean_version(b)}"
      release = []
      release << changelog_filter(`#{base} '#{sha1(a)}..#{sha1(b)}'`)
      next if release.empty?
      release << "#{release_heading}\n#{'='*release_heading.length}\n"
      releases << release.reverse.join("\n")
    end
    if next_release
      last_release = `#{git} rev-list --tags --max-count=1`.strip
      if sha1('HEAD') != sha1(last_release) and not last_release.empty?
        release_tag = `#{git} tag --points-at=#{last_release}`.strip
        release_heading = "#{Time.now.utc.strftime("%Y-%m-%d")}, Version #{clean_version(next_release)}"
        release = []
        release << changelog_filter(`#{base} #{last_release}..`)
        release << "#{release_heading}\n#{'='*release_heading.length}\n" unless release.empty?
        releases << release.reverse.join("\n") unless release.empty?
      end
    end
    releases.reverse.join("\n\n") + "\n"
  end

  def latest
    # --full-history: include individual commits from merged branches
    # --date-order: order commits by date, not topological order
    base = "#{git} log --full-history --date-order --pretty='format:%s (%an)'"
    last_release = `#{git} rev-list --tags --max-count=1`.strip
    if last_release.empty?
      last_release = `git rev-list --max-parents=0 HEAD`.strip
    end
    if sha1('HEAD') != sha1(last_release)
      release_tag = `#{git} tag --points-at=#{last_release}`.strip
      release = []
      release << changelog_filter(`#{base} #{last_release}..`)
      release.reverse.join("\n")
    else
      ''
    end
  end

  def changelog_filter(log)
    log.lines
       .map(&:strip)
       .reject { |line| line =~ /^Merge/ }
       .reject { |line| line =~ /^v?\d+\.\d+\.\d+ \(/ }
       .reject { |line| line =~ /update changes.md/i }
       .reject { |line| line =~ /update changelog/i }
       .to_a.uniq
       .map { |line| " * #{line}\n" }
       .join("\n")
  end

  def sha1(ref)
    if ref.empty? or ref.nil?
      nil
    else
      @sha1[ref]
    end
  end

  def clean_version(tag)
    tag.gsub(/^v/, '')
  end

  private
  attr_reader :repo

  def git
    "git --git-dir=#{ensure_repo}"
  end

  def ensure_repo
    @dir ||= begin
      if system "git rev-parse --show-toplevel"
        `git rev-parse --show-toplevel`.strip + '/.git'
      else
        dir = Dir.mktmpdir
        system "git clone --bare #{repo} #{dir}"
        Pathname(dir)
      end
    end
  end

end

repo = GitRepo.new('.')
options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: slt-changelog [options]'
  opts.on('-v', '--version VERSION', 'Version to describe as next version') do |v|
    options[:version] = v
  end
  opts.on('-s', '--summary', 'Print latest changes only, to stdout') do |s|
    options[:summary] = true
  end
end.parse!

if options[:summary]
  puts repo.latest
else
  filename = ARGV.first || 'CHANGES.md'
  changelog = repo.changelog(options[:version])
  IO.write(filename, changelog)
end