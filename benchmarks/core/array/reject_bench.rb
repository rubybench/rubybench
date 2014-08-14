require "helpers/core/array"

benchmark Array do
  benchmark "#reject" do
    measure "all" do
      def all(times, large_array = $large_array.dup)
        i = 0
        while i < times
          large_array.reject { |v| true }
          i += 1
        end
      end
    end

    measure "none" do
      def none(times, large_array = $large_array.dup)
        i = 0
        while i < times
          large_array.reject { |v| false }
          i += 1
        end
      end
    end

    measure "all (external while)" do
      def all(large_array = $large_array.dup)
        large_array.reject { |v| true }
      end
    end

    measure "none (external while)" do
      def none(large_array = $large_array.dup)
        large_array.reject { |v| false }
      end
    end
  end

  benchmark "#reject!" do
    measure "all" do
      def all(times)
        i = 0
        while i < times
          large_array = $large_array.dup
          large_array.reject! { |v| true }
          i += 1
        end
      end
    end

    measure "none" do
      def none(times, large_array = $large_array.dup)
        i = 0
        while i < times
          large_array.reject! { |v| false }
          i += 1
        end
      end
    end
  end
end