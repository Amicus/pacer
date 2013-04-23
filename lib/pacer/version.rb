module Pacer
  unless const_defined? :VERSION
    VERSION = "1.3.0"

    JAR = "pacer-#{ VERSION }-standalone.jar"
    JAR_PATH = "lib/#{ JAR }"

    START_TIME = Time.now

    BLUEPRINTS_VERSION = "2.4.0-SNAPSHOT"
    PIPES_VERSION = "2.4.0-SNAPSHOT"
    GREMLIN_VERSION = "2.4.0-SNAPSHOT"
  end
end
