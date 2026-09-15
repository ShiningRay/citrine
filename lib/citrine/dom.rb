# backtick_javascript: true
# frozen_string_literal: true

require "native"
require "citrine"
require "citrine/renderer"

module Citrine
  # Web DOM 渲染器（Opal 环境）：实现 Renderer 的平台钩子。
  class DomRenderer < Renderer
    def initialize
      @document = Native(`window.document`)
      super()
    end

    def self.mount_at(element_id, component)
      # F2：一页多根时复用同一渲染器实例（"最后挂载者胜出"会清空先挂载的组件）
      unless Citrine.renderer.is_a?(DomRenderer)
        Citrine.renderer = new
      end
      element = Citrine.renderer.document_element(element_id)
      if element.nil?
        raise %(Citrine.mount_at：找不到 id 为 "#{element_id}" 的元素（确认 HTML 里有 <div id="#{element_id}">…</div> 再挂载）)
      end

      Citrine.mount(component, element)
    end

    def document_element(element_id)
      @document.getElementById(element_id)
    end

    private

    def setup_root(root, element)
      root.dom = element.is_a?(Native::Object) ? element : Native(element)
    end

    def create_dom(node)
      @document.createElement(TAGS[node.type] || node.type.to_s)
    end

    def attach(node, parent)
      parent.dom.appendChild(node.dom)
    end

    # S1-2：view 重跑把节点 append 到末尾；按 anchor 挪回原渲染位（保持兄弟次序）。
    # anchor 已在基类保证非 nil；fragment 无自身 DOM，取它第一个子根作插入锚点。
    def attach_before(node, parent, anchor)
      ref = anchor.type == :fragment ? anchor.children.first&.dom : anchor.dom
      parent.dom.insertBefore(node.dom, ref) if ref
    end

    def detach(node)
      restore_focus(node) # S2-6：卸载带 autofocus 的节点时恢复上一焦点
      parent_dom = node.dom[:parentElement]
      parent_dom.removeChild(node.dom) if parent_dom
    end

    # 幂等：响应式属性重跑时会再次调用（见 Renderer#mount）
    def apply_props(node)
      el = node.dom
      if node.props.key?(:css_class)
        css_class = prop_value(node, node.props[:css_class])
        # A7：数组形式（[:card, :active]）空格 join 后与 SSR class 属性同口径
        el[:className] = css_class.is_a?(Array) ? css_class.join(" ") : css_class.to_s
      end
      el[:placeholder] = prop_value(node, node.props[:placeholder]).to_s if node.props.key?(:placeholder)

      style = resolve_style(node)
      # 响应式 style 换掉整份内联样式：先清掉本次不再出现的旧键（错误态高亮必须能消失）
      track_style_keys(node, style.keys).each { |key| el[:style][Style.camel(key)] = "" }
      style.each { |key, value| el[:style][Style.camel(key)] = value.to_s }

      # S2-2：未消费属性原样透传（id / disabled / aria-* / data-* / title…）。
      # 值可以是响应式的——值翻 false/nil 时属性要能消失，所以记下应用过的键、先清旧键。
      applied = passthrough_props(node)
      applied_names = applied.map { |(name, _)| name }
      (node.applied_attrs || []).each do |stale|
        el.removeAttribute(stale) unless applied_names.include?(stale)
      end
      node.applied_attrs = applied_names
      applied.each { |(name, value)| el.setAttribute(name, value) }

      ensure_events(node) # 复用路径上新增的处理器在此补齐（幂等）
    end

    # 事件监听**按需绑定**：props 里真的有处理器时才 addEventListener，
    # 并记在 node.bound_listeners 上（挂过就不再挂）。事件发生时从 node.props 现取处理器，
    # 所以复用时不需要重绑——新增的处理器由 apply_props → ensure_events 补上。
    # 以前是每个元素无条件挂 4 个监听：多数节点（box/label）根本没有处理器，白挂闭包。
    def bind_events(node)
      ensure_events(node)
    end

    # S2-3：事件面——prop 名 → DOM 事件名（冻结常量，一次定义全实例共享）。
    # 处理器收到平台无关视图（键盘是 KeyEvent，其余是 Citrine::Event），原生细节走 #raw。
    EVENT_DEFS = {
      on_click: :click, on_focus: :focus, on_blur: :blur,
      on_key: :keydown, on_key_up: :keyup,
      on_dblclick: :dblclick, on_contextmenu: :contextmenu,
      on_mouse_enter: :mouseenter, on_mouse_leave: :mouseleave,
      on_mouse_down: :mousedown, on_mouse_up: :mouseup,
      on_wheel: :wheel, on_scroll: :scroll,
      on_submit: :submit, on_paste: :paste,
      on_touch_start: :touchstart, on_touch_move: :touchmove, on_touch_end: :touchend,
      on_pointer_down: :pointerdown, on_pointer_move: :pointermove, on_pointer_up: :pointerup
    }.freeze

    def ensure_events(node)
      owner = node.owner

      EVENT_DEFS.each do |prop, event_name|
        ensure_event(node, event_name, prop, event_name.to_s) do |event|
          handler = node.props[prop]
          next unless handler

          view = event_view(event_name, event)
          # 键盘处理器支持键表形式（on_key: { "Escape" => :x }），走 handle_key
          if prop == :on_key || prop == :on_key_up
            owner.handle_key(handler, view)
          else
            owner.handle_event(handler, view)
          end
        end
      end

      # text_input 的 on_enter / check_box 的 on_change 走同一套按需绑定
      ensure_event(node, :enter, :on_enter, "keydown") do |event|
        ev = Native(event)
        handler = node.props[:on_enter]
        # IME 组合（S2-4）：选词确认的 Enter 不触发 on_enter
        next unless handler && ev[:key] == "Enter" && ev[:isComposing] != true

        owner.handle_event(handler, ev)
      end
      ensure_event(node, :change, :on_change, "change") do |_event|
        handler = node.props[:on_change]
        next unless handler

        # 受控语义（S2-4）：checked 传 Signal 时真正双向绑定——先写回再派发，
        # 处理器读到的是新勾选态（与 text_input 的 value 对称）
        checked = node.props[:checked]
        checked.set(node.dom[:checked]) if checked.is_a?(Signal)
        owner.handle_event(handler, node.dom[:checked])
      end
    end

    # 原生事件 → 平台无关视图：键盘给 KeyEvent，其余给 Citrine::Event
    def event_view(event_name, event)
      return key_event(event) if event_name == :keydown || event_name == :keyup

      ev = Native(event)
      Event.new(event_name.to_s, raw: ev,
                prevent_default: -> { ev.preventDefault },
                stop_propagation: -> { ev.stopPropagation })
    end

    def ensure_event(node, tag, prop, event_name, &listener)
      bound = (node.bound_listeners ||= {})
      return if bound[tag] || !node.props.key?(prop)

      bound[tag] = true
      node.dom.addEventListener(event_name, listener)
    end

    # 全局键盘（G-9）：window 级 keydown，绑定组件生命周期（卸载时由 unmount_component 解绑）。
    # S2-3：带 scope: :focused 的处理器只在焦点落在组件子树内时才分发。
    def register_window_key(component, handler)
      win = Native(`window`)
      scoped = handler.is_a?(Component::WindowKey)
      body = scoped ? handler.handler : handler
      # 不要在 lambda 里用 return/next 之外的提前返回写法：lambda 的 return
      # 走 throw 机制，逃逸到原生 addEventListener 后变成未捕获异常
      listener = ->(event) {
        unless scoped && !focused_in?(component)
          component.handle_key(body, key_event(event))
        end
      }
      win.addEventListener("keydown", listener)
      @window_keys ||= {}
      (@window_keys[component] ||= []) << listener
    end

    # 焦点作用域判定：activeElement 落在组件渲染的子树内（不在 → 包括焦点
    # 在页面上别处或没有焦点元素的情况，都不分发）。
    # 注意走 Native 派发而不是 backtick 插值——node.dom 是包装对象，插值会泄漏包装器。
    def focused_in?(component)
      root = component.respond_to?(:root) ? component.root : nil
      return false unless root && root.dom

      active = @document[:activeElement]
      return false if active.nil?

      root.dom.contains(active)
    end

    def unregister_window_keys(component)
      listeners = @window_keys && @window_keys.delete(component)
      return unless listeners

      win = Native(`window`)
      listeners.each { |listener| win.removeEventListener("keydown", listener) }
    end

    # 原生事件 → Citrine::KeyEvent（平台无关视图；需要的原生细节走 #raw）
    def key_event(event)
      ev = Native(event)
      KeyEvent.new(ev[:key],
                   shift: ev[:shiftKey] == true, meta: ev[:metaKey] == true,
                   ctrl: ev[:ctrlKey] == true, alt: ev[:altKey] == true,
                   raw: ev, prevent_default: -> { ev.preventDefault })
    end

    # S1-5：portal 宿主解析——默认 body；显式 target 是选择器字符串，
    # 解析不到时抛错（不静默回退，否则弹层会挂错地方）
    def resolve_portal_host(target)
      return @document[:body] if target.nil? || target == ""

      host = @document.querySelector(target.to_s)
      raise "Citrine.portal：找不到宿主元素 #{target.inspect}" if host.nil?

      host
    end

    def set_text(node, text)
      # 透明容器没有自己的文本位（借的是父容器的 DOM，写它会砸掉兄弟内容）
      return if node.type == :fragment

      node.dom[:textContent] = text.to_s
      # 镜像进节点的文本槽（与 Canvas/SSR 同口径）：Renderer#run_block 靠它
      # 判定"上一轮写过文本"，本轮没有内容时显式清空，防旧 textContent 残留
      node.text = text
    end

    def finalize(node)
      return if node.type == :root || node.type == :fragment

      setup_autofocus(node) # S2-6：挂载收尾时聚焦（finalize 只在挂载路径跑一次）
    end

    # S2-6：autofocus 原语——挂载后把焦点移到该元素，并记录挂载前的活动元素；
    # 卸载时（detach）恢复焦点到它。tabindex / aria_* 经属性透传（S2-2）直达 DOM。
    # 同样走 Native 派发（node.dom 是包装对象）
    def setup_autofocus(node)
      return unless node.props[:autofocus]

      node.focus_restore_target = @document[:activeElement]
      node.dom.focus
    end

    def restore_focus(node)
      return unless node.props[:autofocus] && (target = node.focus_restore_target)

      target.focus
    end

    def setup_widget(node)
      case node.type
      when :text_input then setup_text_input(node)
      when :check_box  then setup_check_box(node)
      end
    end

    def setup_text_input(node)
      el = node.dom
      el[:type] = node.props[:type] || "text"
      value = node.props[:value]
      if value.is_a?(Signal)
        node.owned_effects << Effect.create { el[:value] = value.get.to_s }
        el.addEventListener("input", ->(_event) { value.set(el[:value]) })
      elsif value.is_a?(String)
        # F20：字面量初值也要落到 DOM，保持与 SSR 输出一致
        el[:value] = value
      end
      # on_enter 不在这里绑：与其它处理器一样走 ensure_events（按需 + 复用时补齐）
    end

    def setup_check_box(node)
      el = node.dom
      el[:type] = "checkbox"
      checked = node.props[:checked]
      if checked.is_a?(Signal)
        # F19：Signal 驱动的勾选态要读信号并保持响应，而不是把对象当 truthy
        node.owned_effects << Effect.create { el[:checked] = checked.get ? true : false }
      else
        el[:checked] = checked ? true : false
      end
      # on_change 同样交给 ensure_events
    end
  end
end
