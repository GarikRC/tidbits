#!/usr/bin/env ruby

require 'rubygems'

gem 'term-ansicolor', '=1.0.5'
require 'term/ansicolor'

class GitCommit
  attr_reader :content
  
  def initialize(content)
    @content = content
  end
  
  def sha
    @content.split[1]
  end

  def to_s
    `git log --pretty=format:"%h %ad %an - %s" #{sha}~1..#{sha}`
  end
  
  def unmerged?
    content =~ /^\+/
  end
  
  def equivalent?
    content =~ /^\-/
  end
end

class GitBranch
  attr_reader :name, :commits
  
  def initialize(name, commits)
    @name = name
    @commits = commits
  end
  
  def unmerged_commits
    commits.select{ |commit| commit.unmerged? }
  end

  def equivalent_commits
    commits.select{ |commit| commit.equivalent? }
  end

end

class GitBranches < Array
  def self.clean_branch_output(str)
    str.split(/\n/).map{ |e| e.strip.gsub(/\*\s+/, '') }.reject{ |branch| branch =~ /\b#{Regexp.escape(UPSTREAM)}\b/ }.sort
  end
  
  def self.local_branches
    clean_branch_output `git branch`
  end
  
  def self.remote_branches
    clean_branch_output `git branch -r`
  end
  
  def self.load(options)
    git_branches = new
    branches = if options[:local]
      local_branches
    elsif options[:remote]
      remote_branches
    end
    
    branches.each do |branch|
      raw_commits = `git cherry -v #{UPSTREAM} #{branch}`.split(/\n/).map{ |c| GitCommit.new(c) }
      git_branches << GitBranch.new(branch, raw_commits)
    end
    git_branches
  end
  
  def unmerged
    reject{ |branch| branch.commits.empty? }.sort_by{ |branch| branch.name }
  end
  
  def any_missing_commits?
    select{ |branch| branch.commits.any? }.any?
  end
end

class GitUnmerged
  VERSION = "1.0.1"
  
  include Term::ANSIColor

  attr_reader :branches
  
  def initialize(args)
    @options = {}
    extract_options_from_args(args)
  end
  
  def load
    @branches ||= GitBranches.load(:local => local?, :remote => remote?)
    @branches.reject!{|b| @options[:exclude].include?(b.name)} if @options[:exclude].is_a?(Array)
  end
  
  def print_overview
    load
    if @options[:exclude] && @options[:exclude].length > 0
      puts "The following branches have been excluded"
      @options[:exclude].each do |branch_name|
        puts "  #{branch_name}"
      end
      puts
    end
    if branches.any_missing_commits?
      puts "The following branches possibly have commits not merged to #{upstream}:"
      branches.each do |branch|
        num_unmerged = yellow(branch.unmerged_commits.size.to_s)
        num_equivalent = green(branch.equivalent_commits.size.to_s)
        puts %|  #{branch.name} (#{num_unmerged}/#{num_equivalent} commits)|
      end
    end
  end
  
  def print_help
    puts <<-EOT.gsub(/^\s+\|/, '')
      |Usage: #{$0} [-a] [--upstream <branch>] [--remote]
      |
      |This script wraps the "git cherry" command. It reports the commits from all local
      |branches which have not been merged into an upstream branch. 
      |
      |  #{yellow("yellow")} commits have not been merged
      |  #{green("green")} commits have equivalent changes in <upstream> but different SHAs
      |
      |The default upstream is 'master'. 
      |
      |OPTIONS:
      |  -a   display all unmerged commits (verbose)
      |  --remote   compare remote branches instead of local branches
      |  --upstream <branch>   specify a specific upstream branch
      |  --exclude <branch>[,<branch>,...]   specify a comma-separated list of branches to exclude
      | 
      |EXAMPLE: check for all unmerged commits
      |  #{$0}
      |
      |EXAMPLE: check for all unmerged commits and merged commits (but with a different SHA)
      |  #{$0} -a
      | 
      |EXAMPLE: use a different upstream than master
      |  #{$0} --upstream otherbranch
      |
      |EXAMPLE: compare remote branches against origin/master
      |  #{$0} --remote
      |
      |GITCONFIG:
      |  If you name this file git-unmerged and place it somewhere in your PATH
      |  you will be able to type "git unmerged" to use it. If you'd like to name
      |  it something else and still refer to it with "git unmerged" then you'll
      |  need to set up an alias:
      |      git config --global alias.unmerged \\!#{$0}
      |
      |Version: #{VERSION}
      |Author: Zach Dennis <zdennis@mutuallyhuman.com>
    EOT
    exit
  end
  
  def print_version
    puts "#{VERSION}"
  end
    
  def branch_description
    local? ? "local" : "remote"
  end
  
  def print_specifics
    load
    if branches.any_missing_commits?
      print_breakdown
    else
      puts "There are no #{branch_description} branches out of sync with #{upstream}"
    end
  end
  
  def print_breakdown
    puts "Below is a breakdown for each branch. Here's a legend:"
    puts
    print_legend
    branches.each do |branch|
      puts
      print "#{branch.name}:"
      if branch.unmerged_commits.empty? && !show_equivalent_commits?
        print "(no umerged commits, must have merged commits with different SHAs)\n" 
      else
        puts
      end
      branch.unmerged_commits.each { |commit| puts yellow(commit.to_s) }

      if show_equivalent_commits?
        branch.equivalent_commits.each do |commit|
          puts green(commit.to_s)
        end
      end
    end
  end
  
  def print_legend
    load
    puts "  " + yellow("yellow") + " commits have not been merged"
    puts "  " + green("green") + " commits have equivalent changes in #{UPSTREAM} but different SHAs" if show_equivalent_commits?
  end
  
  def show_help? ; @options[:show_help] ; end
  def show_equivalent_commits? ; @options[:show_equivalent_commits] ; end
  def show_version? ; @options[:show_version] ; end

  def upstream
    if @options[:upstream]
      @options[:upstream]
    elsif local?
      "master"
    elsif remote?
      "origin/master"
    end
  end
  
  private
  
  def extract_options_from_args(args)
    if args.include?("--remote")
      @options[:remote] = true
    else
      @options[:local] = true
    end
    @options[:show_help] = true if args.include?("-h") || args.include?("--help")
    @options[:show_equivalent_commits] = true if args.include?("-a")
    @options[:show_version] = true if args.include?("-v") || args.include?("--version")
    if index=args.index("--upstream")
      @options[:upstream] = args[index+1]
    end
    if index=args.index("--exclude")
      @options[:exclude] = args[index+1].split(',')
    end
  end
  
  def local? ; @options[:local] ; end
  def remote? ; @options[:remote] ; end
end


unmerged = GitUnmerged.new ARGV
UPSTREAM = unmerged.upstream
if unmerged.show_help?
  unmerged.print_help
  exit
elsif unmerged.show_version?
  unmerged.print_version
  exit
else
  unmerged.print_overview
  puts
  unmerged.print_specifics
end
