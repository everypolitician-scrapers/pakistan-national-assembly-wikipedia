#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

def scraped(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

class MemberList < Scraped::HTML
  decorator WikidataIdsDecorator::Links

  field :members do
    member_rows.map { |tr| fragment(tr => MemberRow).to_h }
  end

  def parties
    @parties ||= members.reject { |m| m[:party_id].nil? }.map { |m| [ m[:party], m[:party_id] ] }.to_h
  end

  private

  def members_table
    noko.xpath('//h2[span[@id="Members"]]/following-sibling::table[1]')
  end

  def member_rows
    # all rows with a link in the 4th column
    members_table.xpath('.//tr[td[4][a]]')
  end
end

class MemberRow < Scraped::HTML
  field :id do
    member.attr('wikidata') rescue binding.pry
  end

  field :name do
    member.text.tidy
  end

  field :area_id do
    constituency_link && constituency_link.attr('wikidata')
  end

  field :area do
    constituency.text.tidy
  end

  field :region do
    noko.at_css('th').text
  end

  field :party_id do
    td[2].css('a/@wikidata').map(&:text).first
  end

  field :party do
    td[2].text.tidy
  end

  field :start_date do
    Date.parse(td[4].text.tidy).to_s rescue binding.pry
  end

  private

  def td
    noko.css('td')
  end

  def member
    td[3].css('a').first
  end

  def constituency_link
    td[1].css('a').first
  end

  def constituency
    td[1]
  end
end

url = 'https://en.wikipedia.org/wiki/List_of_members_of_the_14th_National_Assembly_of_Pakistan'

page = scraped(url => MemberList)
data = page.members.each do |mem|
  mem[:party_id] ||= page.parties[mem[:party]]
end
data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[id area], data)
