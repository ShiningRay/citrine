# frozen_string_literal: true

require "json"
require "base64"

module Citrine
  # source map 还原（T-B3 后半）：把 Opal 产物的 JS 抛错位置还原到 .rb 文件与行号。
  #
  # 支持两种 map 形态：
  #   - 普通 map：顶层 mappings/sources
  #   - indexed map：Opal 产出的 sections 内嵌多段 map
  #
  # 用法（拿到未捕获异常的 JS 行号后）：
  #   map  = Citrine::SourceMap.load("counter.js")
  #   loc  = Citrine::SourceMap.locate(map, js_line, js_column)
  #   loc  # => { source: "counter.rb", line: 12, column: 5 }
  class SourceMap
    B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
          .chars.each_with_index.to_h.freeze

    attr_reader :raw

    # 从 .js 文件读取内联 base64 map（Opal 默认产物形态）
    def self.load(js_path)
      body = File.read(js_path)
      match = body.match(/sourceMappingURL=data:application\/json;base64,([A-Za-z0-9+\/=]+)/)
      raise ArgumentError, "#{js_path} 内没有内联 source map" unless match

      new(JSON.parse(Base64.decode64(match[1])))
    end

    def initialize(raw)
      @raw = raw
    end

    # 把生成的 JS 位置（1-based 行）还原到原始 .rb 位置。
    # 返回 { source:, line:, column: } 或 nil（该位置无映射信息）。
    def locate(line, column = 0)
      line0 = line - 1 # 内部统一 0-based 生成行（spec 的 section offset 即 0-based）
      if raw["sections"]
        section, offset = find_section(line0, column)
        return nil unless section

        off_line, off_col = offset
        locate_in(section["map"], line0 - off_line + 1, column - off_col)
      else
        locate_in(raw, line, column)
      end
    end

    # map 覆盖的所有原始文件
    def sources
      if raw["sections"]
        raw["sections"].flat_map { |s| s.dig("map", "sources") || [] }.compact
      else
        raw["sources"] || []
      end
    end

    private

    # 选取起始位置 <= 目标位置的最后一个 section（sections 按 offset 升序）。
    # offset 兼容规范 hash 形态 {"line":, "column":}（部分工具也用数组）。
    def find_section(line0, _column0)
      best = nil
      best_offset = nil
      raw["sections"].each do |section|
        offset = section["offset"]
        off_line = offset.is_a?(Array) ? offset[0] : offset["line"].to_i
        off_col = offset.is_a?(Array) ? (offset[1] || 0) : offset["column"].to_i
        if off_line <= line0
          best = section
          best_offset = [off_line, off_col]
        end
      end
      best ? [best, best_offset] : nil
    end

    def locate_in(map, line, column)
      decoded = decoded_lines(map)
      return nil if line <= 0 || line > decoded.size

      segments = decoded[line - 1]
      seg = segments.reverse.find { |(gen_col, *)| gen_col <= column }
      return nil if seg.nil? || seg[1].nil?

      sources = map["sources"] || []
      return nil if sources[seg[1]].nil?

      # src_line/src_col 以 0 计，行号转 1-based
      { source: sources[seg[1]], line: seg[2] + 1, column: seg[3] }
    end

    # 全量预解码 mappings：生成列每行重置，源索引/源行/源列跨行累积（spec 语义）。
    # 每行产出 [gen_col, src_idx, src_line, src_col] 段（1 字段段仅推进 gen_col）。
    def decoded_lines(map)
      @decoded_cache ||= {}
      @decoded_cache[map] ||= begin
        src_idx = 0
        src_line = 0
        src_col = 0
        (map["mappings"] || "").split(";").map do |line|
          gen_col = 0
          line.split(",").filter_map do |segment|
            next if segment.empty?

            fields = decode_vlq(segment)
            gen_col += fields[0]
            if fields.size >= 4
              src_idx += fields[1]
              src_line += fields[2]
              src_col += fields[3]
              [gen_col, src_idx, src_line, src_col]
            end
          end
        end
      end
    end

    # Base64 VLQ 解码
    def decode_vlq(segment)
      values = []
      shift = 0
      value = 0
      segment.each_char do |ch|
        digit = B64[ch] or raise ArgumentError, "非法 base64 VLQ 字符: #{ch.inspect}"
        cont = (digit & 32) != 0
        digit &= 31
        value += digit << shift
        if cont
          shift += 5
        else
          negative = (value & 1) == 1
          value >>= 1
          values << (negative ? -value : value)
          value = 0
          shift = 0
        end
      end
      values
    end
  end
end
