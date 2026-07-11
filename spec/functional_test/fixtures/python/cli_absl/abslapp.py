from absl import app, flags

FLAGS = flags.FLAGS

flags.DEFINE_string("name", "world", "Who to greet.")
flags.DEFINE_integer("port", 8080, "Port to bind.")
flags.DEFINE_bool("verbose", False, "Enable verbose output.")
flags.DEFINE_enum("mode", "dev", ["dev", "prod"], "Run mode.")


def main(argv):
    print(f"Hello {FLAGS.name} on port {FLAGS.port} ({FLAGS.mode})")


if __name__ == "__main__":
    app.run(main)
