#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "erb"
require "octokit"
require "yaml"

class Client
  attr_reader :octokit, :repository, :contents

  def initialize(octokit, repository)
    @octokit = octokit
    @repository = repository
    @contents = {}
  end

  def branch_protection?
    octokit.branch_protection(repository.full_name, "main")
  rescue Octokit::Forbidden
    true # can't check branch protection, assume it's enabled
  end

  def contents(path)
    @contents[path] ||= octokit.contents(repository.full_name, path: path)
  rescue Octokit::NotFound
  end

  def contents?(path)
    !contents(path).nil?
  end

  def contents_decoded(path)
    response = contents(path)
    Base64.decode64(response.content) if response
  end

  def default_branch
    octokit.repo(repository.full_name).default_branch
  end

  def issues_empty?
    octokit.issues(repository.full_name).empty?
  end

  def license?
    !octokit.repo(repository.full_name).license.nil?
  end
end

class Repository
  attr_reader :owner, :name, :full_name, :tags

  def initialize(owner, name, tags = [])
    @owner = owner
    @name = name
    @full_name = "#{owner}/#{name}"
    @tags = tags
  end
end

class Check
  SUCCESS = 1
  FAILURE = 2
  NOT_APPLICABLE = 3

  attr_reader :name, :tags, :block

  def initialize(name, tags = [], &block)
    @name = name
    @tags = tags
    @block = block
  end

  def call(client)
    if tags.empty? || (client.repository.tags & tags).any?
      block.call(client) ? SUCCESS : FAILURE
    else
      NOT_APPLICABLE
    end
  end
end

class Result
  attr_reader :octokit, :repository

  def initialize(octokit, repository)
    @octokit = octokit
    @repository = repository
  end

  def full_name
    repository.full_name
  end

  def each(checks)
    client = Client.new(octokit, repository)

    checks.each do |check|
      yield check.call(client)
    end
  end
end

repositories = [
  Repository.new("kddnewton", "active_record-union_relation", ["ruby", "gem"]),
  Repository.new("kddnewton", "attribute_extras", ["ruby", "gem"]),
  Repository.new("kddnewton", "bundler-console", ["ruby", "gem"]),
  Repository.new("kddnewton", "exreg", ["ruby", "gem"]),
  Repository.new("kddnewton", "fast_camelize", ["ruby", "gem"]),
  Repository.new("kddnewton", "fast_parameterize", ["ruby", "gem"]),
  Repository.new("kddnewton", "fast_underscore", ["ruby", "gem"]),
  Repository.new("kddnewton", "gemfilelint", ["ruby", "gem"]),
  Repository.new("kddnewton", "hollaback", ["ruby", "gem"]),
  Repository.new("kddnewton", "humidifier", ["ruby", "gem"]),
  Repository.new("kddnewton", "minitest-keyword", ["ruby", "gem"]),
  Repository.new("kddnewton", "prettier-plugin-brainfuck", ["javascript"]),
  Repository.new("kddnewton", "prettier-plugin-ini", ["javascript"]),
  Repository.new("kddnewton", "ragel-bitmap", ["ruby", "gem"]),
  Repository.new("kddnewton", "rails-pattern_matching", ["ruby", "gem"]),
  Repository.new("kddnewton", "thor-hollaback", ["ruby", "gem"]),
  Repository.new("kddnewton", "yarv", ["ruby"]),
  Repository.new("prettier", "plugin-ruby", ["ruby", "javascript"]),
  Repository.new("prettier", "plugin-xml", ["javascript"]),
  Repository.new("ruby-syntax-tree", "node-syntax-tree", ["javascript"]),
  Repository.new("ruby-syntax-tree", "prettier_print", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-bf", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-css", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-haml", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-json", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-rbs", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-translator", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "syntax_tree-xml", ["ruby", "gem"]),
  Repository.new("ruby-syntax-tree", "vscode-syntax-tree", ["javascript"]),
  Repository.new("vue-a11y", "eslint-plugin-vuejs-accessibility", ["javascript"])
]

checks = [
  Check.new("AutoMerge workflow") { |client| client.contents?(".github/workflows/auto-merge.yml") },
  Check.new("Branch protection") { |client| client.branch_protection? },
  Check.new("Code of conduct") { |client| client.contents?("CODE_OF_CONDUCT.md") },
  Check.new("Dependabot") { |client| client.contents?(".github/dependabot.yml") },
  Check.new("Dependabot - bundler", ["ruby"]) { |client| (contents = client.contents_decoded(".github/dependabot.yml")) && YAML.load(contents)["updates"].any? { |update| update["package-ecosystem"] == "bundler" } },
  Check.new("Dependabot - GitHub Actions") { |client| (contents = client.contents_decoded(".github/dependabot.yml")) && YAML.load(contents)["updates"].any? { |update| update["package-ecosystem"] == "github-actions" } },
  Check.new("Dependabot - npm", ["javascript"]) { |client| (contents = client.contents_decoded(".github/dependabot.yml")) && YAML.load(contents)["updates"].any? { |update| update["package-ecosystem"] == "npm" } },
  Check.new("Gemspec - rubygems_mfa_required", ["gem"]) { |client| client.contents_decoded("#{client.repository.name}.gemspec")&.include?("rubygems_mfa_required") },
  Check.new("GitHub Actions") { |client| client.contents?(".github/workflows/main.yml") },
  Check.new("License") { |client| client.license? },
  Check.new("main branch") { |client| client.default_branch == "main" },
  Check.new("Open issues") { |client| client.issues_empty? },
  Check.new("README") { |client| client.contents?("README.md") },
  Check.new("README - GitHub Actions badge") { |client| client.contents_decoded("README.md")&.include?("https://github.com/#{client.repository.full_name}/actions") },
  Check.new("README - rubygems.org badge", ["gem"]) { |client| client.contents_decoded("README.md")&.include?("(https://rubygems.org/gems/#{client.repository.name})") },
  Check.new("Syntax Tree formatting", ["ruby"]) { |client| client.contents_decoded("Gemfile.lock").then { |content| !content || content.include?("syntax_tree") } }
]

filter = ARGV.first
repositories.select! { |repository| repo.full_name.include?(filter) } if filter

octokit = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"])
results = repositories.map { |repository| Result.new(octokit, repository) }

puts ERB.new(DATA.read, trim_mode: "-").result_with_hash(checks: checks, results: results)

__END__
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="initial-scale=1, maximum-scale=5">
    <title>kddnewton repositories</title>
  </head>
  <body>
    <table>
      <thead>
        <tr>
          <th>Repository</th>
          <%- checks.each do |check| -%>
          <th><%= check.name %></th>
          <%- end -%>
        </tr>
      </thead>
      <tbody>
        <%- results.each do |result| -%>
        <tr>
          <td><%= result.full_name %></td>
          <%- result.each(checks) do |status| -%>
          <%- case status -%>
          <%- when Check::SUCCESS -%>
          <td>✓</td>
          <%- when Check::FAILURE -%>
          <td>✗</td>
          <%- when Check::NOT_APPLICABLE -%>
          <td>-</td>
          <%- end -%>
          <%- end -%>
        </tr>
        <%- end -%>
      </tbody>
    </table>
  </body>
</html>