module Dao
  class Api
    class << Api
      def interfaces
        @interfaces ||= Map.new
      end

      def interface(path, &block)
        api = self
        path = Path.new(path)

        method =
          module_eval{ 
            define_method(path + '/interface', &block)
            instance_method(path + '/interface')
          }


        interface = Interface.new(
          'api' => api,
          'path' => path,
          'method' => method,
          'doc' => docs.pop
        )

        interfaces[path] = interface
      end

      alias_method('call', 'interface')

      def description(string)
        doc(:description => Dao.unindent(string))
      end
      alias_method('desc', 'description')

      def doc(*args)
        docs.push(Map[:description, nil]) if docs.empty?
        doc = docs.last
        options = Dao.options_for!(args)
        if options.empty?
          options[:description] = args.join(' ')
        end
        doc.update(options)
        doc
      end

      def docs
        @docs ||= []
      end

      def index
        index = Map.new
        interfaces.each do |path, interface|
          index[path] = interface.doc || {'description' => path}
        end
        index
      end
    end

    def call(path = '/index', params = {}, options = {})
      api = self
      path = Path.new(path)
      interface = interfaces[path]

      unless interface
        return index if path == '/index'
        raise(NameError, "NO SUCH INTERFACE: #{ path }")
      end

      options = Map.options(options || {})

      params = Dao.parse(path, params, options)

      context = Context.new(
        :api => api,
        :interface => interface,
        :params => params
      )

      callstack(context) do
        catching(:result){ context.call() }
      end

      context.result
    end

    def index
      result = Result.new('/index')
      result.data.update(self.class.index)
      result
    end

    def interfaces
      self.class.interfaces
    end

    def context
      callstack.last || raise('no context!')
    end

    def result
      context.result
    end

    def params
      result.params
    end

    def errors
      result.errors
    end

    def apply(hash = {})
      data.apply(hash)
    end

    def update(hash = {})
      data.update(hash)
    end

    def default(*args)
      hash = Map.options_for!(args)
      if hash.empty?
        value = args.pop
        key = args
        hash = {key => value}
      end
      data.apply(hash)
    end

    def status(*args, &block)
      result.status(*args, &block)
    end

    def status!(*args, &block)
      status(*args, &block)
      return!
    end

    def data(*args)
      if args.empty?
        result.data
      else
        result.data.replace(*args)
      end
    end

    def data!(*args)
      result.data.replace(*args)
      valid!
    end

    def update(*args, &block)
      data.update(*args, &block)
    end

    def replace(*args, &block)
      data.replace(*args, &block)
    end

    def validations
      result.validations
    end

    def validates(*args, &block)
      result.validates(*args, &block)
    end

    def validate
      result.validate
    end

    def valid?
      result.valid?
    end

    def validate!
      result.validate!
    end

    def valid!
      result.valid!
    end

    include Validations::Common

    def parameter(*args, &block)
      options = Map.options_for!(args)

      keys = []
      lists_of_keys = args, Array(options[:keys]), Array(options[:or])
      lists_of_keys.each do |list|
        list = [list] unless list.first.is_a?(Array)
        next if list.flatten.compact.empty?
        list.each{|key| keys.push(key)}
      end

      raise(ArgumentError, 'no keys') if keys.empty?

      missing = Object.new.freeze
      value = missing

      keys.each do |key|
        if params.has?(key)
          value = params.get(key)
          break
        end
      end

      if value == missing
        message =
          case options[:error]
            when nil, false
              nil
            when true
              missed = keys.map{|key| key.join('.')}.join(' or ')
              "#{ missed } (paramter missing)"
            else
              message = options[:error].to_s
          end
        errors.add(message) if message

        status(options[:status]) if options[:status]
        return! if options[:return!]
      end

      value == missing ? nil : value
    end

    def parameter!(*args, &block)
      options = args.last.is_a?(Hash) ? Map.for(args.pop) : Map.new
      args.push(options)
      options[:error] = true unless options.has_key?(:error)
      options[:return!] = true unless options.has_key?(:return!)
      options[:status] = 412 unless options.has_key?(:status)
      parameter(*args, &block)
    end

    def return!(*value)
      throw(:result, *value)
    end

    def set(*args, &block)
      result.data.set(*args, &block)
    end

    def get(*args, &block)
      params.data.get(*args, &block)
    end

    def callstack(context = nil, &block)
      @callstack ||= []

      if block and context
        begin
          @callstack.push(context)
          return block.call()
        ensure
          @callstack.pop
        end
      else
        @callstack
      end
    end

    def catching(label = :result, &block)
      @catching ||= []

      if block
        begin
          @catching.push(label)
          catch(label, &block)
        ensure
          @catching.pop
        end
      else
        @catching.last
      end
    end

    def catching_results(&block)
      catching(:result, &block)
    end

    def catching?
      catching
    end

    def catching_results?
      catching == :result
    end

    def respond_to?(*args)
      super(*args) || super(Path.absolute_path_for(*args))
    end
  end
end
