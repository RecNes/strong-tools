#!/usr/bin/env ruby

require 'date'
require 'optparse'
require 'pathname'

class GitRepo
  def initialize(repo='.')
    @repo = repo
    @sha1 = Hash.new do |cache, ref|
      cache[ref] = `#{git} rev-list -n 1 #{ref}`.strip
    end
    @date_of = Hash.new do |cache, ref|
      d = `#{git} log --date=iso --format="%ad" -n1 "#{ref}"`.strip
      cache[ref] = d.split(' ')[0]
    end
  end

  def changelog(next_release=false)
    # --full-history: include individual commits from merged branches
    # --date-order: order commits by date, not topological order
    base = "#{git} log --full-history --date-order --pretty=\"format:%s (%an)\""
    releases = []
    tags = tags_by_topo

    # First release doesn't have a full changelog
    if tags.empty?
      release_heading = "#{Time.now.utc.strftime("%Y-%m-%d")}, Version #{clean_version(next_release || '0.0.0')}"
    else
      release_heading = "#{date_of(tags.first)}, Version #{clean_version(tags.first)}"
    end
    release = []
    release << " * First release!"
    release << "#{release_heading}\n#{'='*release_heading.length}\n"
    releases << release.reverse.join("\n")

    # 2nd, 3rd, etc. releases have changes between them
    tags.each_cons(2) do |a,b|
      release_heading = "#{date_of(b)}, Version #{clean_version(b)}"
      release = []
      release << changelog_filter(clean_version(b), `#{base} "#{sha1(a)}..#{sha1(b)}"`).join("\n")
      next if release.empty?
      release << "#{release_heading}\n#{'='*release_heading.length}\n"
      releases << release.reverse.join("\n")
    end

    # Release we are pretending HEAD is
    if next_release and tags.length > 0 and sha1('HEAD') != sha1(tags.last)
      release_heading = "#{Time.now.utc.strftime("%Y-%m-%d")}, Version #{clean_version(next_release)}"
      release = []
      release << changelog_filter(clean_version(next_release), `#{base} #{sha1(tags.last)}..`).join("\n")
      release << "#{release_heading}\n#{'='*release_heading.length}\n" unless release.empty?
      releases << release.reverse.join("\n") unless release.empty?
    end
    releases.reverse.join("\n\n") + "\n"
  end

  # Tags that are ancestors of HEAD, oldest to newest
  def tags_by_topo
    all_tags = `#{git} tag`.strip.lines.map(&:strip)
    branch_history = `git rev-list --simplify-by-decoration --topo-order HEAD`
    branch_revs = branch_history.lines.map(&:strip).reverse
    branch_tags = all_tags.select { |tag|
      # Filter out tags that are not part of the current branch's history
      branch_revs.include? sha1(tag)
    }
    branch_tags.sort_by { |tag|
      # sort by the order of the branch_revs list
      branch_revs.index sha1(tag)
    }
  end

  def latest(version=false)
    # --full-history: include individual commits from merged branches
    # --date-order: order commits by date, not topological order
    base = "#{git} log --full-history --date-order --pretty=\"format:%s (%an)\""
    last_release = sha1(tags_by_topo.last)
    release = []
    if last_release.nil?
      release << ' * First release!'
    elsif sha1('HEAD') != sha1(last_release)
      release << changelog_filter(version, `#{base} #{last_release}..`).join
    end
    if version
      release << "#{clean_version(version)}\n\n"
    end
    release.reverse.join
  end

  def changelog_filter(v, log)
    log.lines
       .map(&:strip)
       .reject { |line| line.start_with?(v + ' (') }
       .reject { |line| line =~ /^Merge/ }
       .reject { |line| line =~ /^v?\d+\.\d+\.\d+ \(/ }
       .reject { |line| line =~ /update changes.md/i }
       .reject { |line| line =~ /update changelog/i }
       .to_a.uniq
       .map { |line| " * #{line}\n" }
  end

  def sha1(ref)
    if ref.nil? or ref.empty?
      nil
    else
      @sha1[ref]
    end
  end

  def date_of(ref)
    if ref.nil? or ref.empty?
      nil
    else
      @date_of[sha1(ref)]
    end
  end

  def clean_version(tag)
    tag.gsub(/^v/, '')
  end

  private
  attr_reader :repo

  def git
    "git"
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
  puts repo.latest(options[:version])
else
  filename = ARGV.first || 'CHANGES.md'
  changelog = repo.changelog(options[:version])
  IO.write(filename, changelog)
end
