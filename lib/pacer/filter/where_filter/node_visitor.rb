module Pacer
  module Filter
    module WhereFilter
      class NodeVisitor
        import com.tinkerpop.pipes.filter.OrFilterPipe
        import com.tinkerpop.pipes.filter.FilterPipe
        import com.tinkerpop.pipes.filter.AndFilterPipe
        import com.tinkerpop.pipes.filter.OrFilterPipe
        import com.tinkerpop.pipes.filter.ObjectFilterPipe
        import com.tinkerpop.pipes.transform.PropertyPipe
        import com.tinkerpop.pipes.transform.HasCountPipe
        NeverPipe = Pacer::Pipes::NeverPipe
        IdentityPipe = Pacer::Pipes::IdentityPipe
        PropertyComparisonFilterPipe = Pacer::Pipes::PropertyComparisonFilterPipe
        Pipeline = Pacer::Pipes::Pipeline
        CrossProductTransformPipe = Pacer::Pipes::CrossProductTransformPipe
        UnaryTransformPipe = Pacer::Pipes::UnaryTransformPipe

        Filters = {
          '==' => FilterPipe::Filter::EQUAL,
          '='  => FilterPipe::Filter::EQUAL,
          '!=' => FilterPipe::Filter::NOT_EQUAL,
          '>'  => FilterPipe::Filter::GREATER_THAN,
          '<'  => FilterPipe::Filter::LESS_THAN,
          '>=' => FilterPipe::Filter::GREATER_THAN_EQUAL,
          '<=' => FilterPipe::Filter::LESS_THAN_EQUAL
        }

        ReverseFilters = Filters.merge(
          '<'  => FilterPipe::Filter::GREATER_THAN,
          '>'  => FilterPipe::Filter::LESS_THAN,
          '<=' => FilterPipe::Filter::GREATER_THAN_EQUAL,
          '>=' => FilterPipe::Filter::LESS_THAN_EQUAL
        )

        class Pipe
          def initialize(pipe, *args)
            @pipe = pipe
            @args = args
          end

          attr_reader :pipe
          attr_reader :args

          def inspect(depth = 0)
            ([" " * depth + pipe.to_s] + args.map do |arg|
              if arg.is_a? Pipe or arg.is_a? Value
                arg.inspect(depth + 2)
              else
                " " * (depth + 2) + arg.to_s
              end
            end).join "\n"
          end

          def build
            pipe.new *build_args
          end

          def build_args
            args.map do |arg|
              if arg.is_a? Pipe
                arg.build
              elsif arg.is_a? Value
                arg.value
              else
                arg
              end
            end
          end
        end

        class Value
          def initialize(value)
            @value = value
          end

          def pipe; end
          attr_reader :value

          def inspect(depth = 0)
            " " * depth + "Value: #{ value.inspect }"
          end

          def build
            value
          end

          def values!
            if value.is_a? Array
              value.map do |v|
                if v.is_a? Value
                  v.values!
                else
                  raise "Arrays may not contain other properties"
                end
              end
            else
              value
            end
          end
        end


        COMPARITORS = %w[ == != > < >= <= ] 
        METHODS = %w[ + - * / % ]
        VALID_OPERATIONS = COMPARITORS + METHODS

        class << self

          def build_comparison(a, b, name)
            # TODO: support regex matches
            regex = %w[ =~ !~ ]

            raise "Operation not supported: #{ name }" unless VALID_OPERATIONS.include? name
            if COMPARITORS.include? name
              if a.is_a? Value and b.is_a? Value
                if a.value.send name, b.value
                  Pipe.new IdentityPipe
                else
                  Pipe.new NeverPipe
                end
              elsif a.pipe == PropertyPipe and b.pipe == PropertyPipe
                Pipe.new PropertyComparisonFilterPipe, a, b, Filters[name]
              elsif b.pipe == PropertyPipe and a.is_a? Value
                Pipe.new Pipeline, b, Pipe.new(ObjectFilterPipe, a, ReverseFilters[name])
              else
                Pipe.new Pipeline, a, Pipe.new(ObjectFilterPipe, b, Filters[name])
              end
            elsif METHODS.include? name
              if a.is_a? Value and b.is_a? Value
                Value.new a.value.send(name, b.value)
              else
                Pipe.new CrossProductTransformPipe, name, a, b
              end
            end
          end 

          def visitAndNode(node)
            a = node.first_node.accept(self)
            b = node.second_node.accept(self)

            if a.pipe == AndFilterPipe and b.pipe == AndFilterPipe
              Pipe.new AndFilterPipe, *a.args, *b.args
            elsif a.pipe == AndFilterPipe
              Pipe.new AndFilterPipe, *a.args, b
            elsif b.pipe == AndFilterPipe
              Pipe.new AndFilterPipe, a, *b.args
            else
              Pipe.new AndFilterPipe, a, b
            end
          end 

          def visitArrayNode(node)
            Value.new Value.new(node.child_nodes.map { |n| n.accept self }).values!
          end 

          def visitBignumNode(node)
            Value.new node.value.to_s
          end

          def visitCallNode(node)
            a = node.receiver_node.accept(self)
            if node.args_node
              b = node.args_node.child_nodes.first.accept(self)
              build_comparison(a, b, node.name)
            else
              return a if node.name == '+'
              if a.is_a? Value
                Value.new a.value.send(a.name)
              elsif a.pipe == PropertyPipe
                Pipe.new(UnaryTransformPipe, node.name, a)
              else
                case node.name
                when '!'
                  # Special case for "a == 1 and not (b == 1)", etc.
                  Pipe.new(Pipeline, a, Pipe.new(HasCountPipe, -1, 0), Pipe.new(ObjectFilterPipe, true, Filters['==']))
                else
                  raise 'not sure'
                end
              end
            end
          end

          def visitFalseNode(node)
            Pipe.new NeverPipe
          end 

          def visitFixnumNode(node)
            Value.new node.value
          end 

          def visitFloatNode(node)
            Value.new node.value
          end

          def visitHashNode(node)
            Value.new Hash[*node.child_nodes.first.accept(self).value.map { |v| v.value }]
          end

          def visitLocalAsgnNode(node)
            a = Pipe.new PropertyPipe, node.name
            b = node.value_node.accept(self)
            build_comparison(a, b, '==')
          end 

          def visitLocalVarNode(node)
            Pipe.new PropertyPipe, node.name
          end

          def visitNewlineNode(node)
            node.next_node.accept(self)
          end 

          def visitNilNode(node)
            Value.new nil
          end 

          def visitOrNode(node)
            a = node.first_node.accept(self)
            b = node.second_node.accept(self)
            if a.pipe == OrFilterPipe and b.pipe == OrFilterPipe
              Pipe.new OrFilterPipe, *a.args, *b.args
            elsif a.pipe == OrFilterPipe
              Pipe.new OrFilterPipe, *a.args, b
            elsif b.pipe == OrFilterPipe
              Pipe.new OrFilterPipe, a, *b.args
            else
              Pipe.new OrFilterPipe, a, b
            end
          end 

          def visitRootNode(node)
            pipe = node.body_node.accept self
            if pipe.pipe == AndFilterPipe or pipe.pipe == OrFilterPipe
              pipe
            elsif pipe.is_a? Value
              if pipe.value
                Pipe.new IdentityPipe
              else
                Pipe.new NeverPipe
              end
            else
              Pipe.new AndFilterPipe, pipe
            end
          end 

          def visitStrNode(node)
            Value.new node.value
          end 

          def visitSymbolNode(node)
            Value.new node.name
          end 

          def visitTrueNode(node)
            Pipe.new IdentityPipe
          end 

          def visitVCallNode(node)
            Pipe.new PropertyPipe, node.name
          end 

          def visitZArrayNode(node)
            Value.new []
          end
        end
      end
    end
  end
end
