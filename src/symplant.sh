#! /usr/bin/env bash

__version="20240217-0.2"
#
# Project directory
PROJECT_DIR=${1:-./}

[[ -s "$PROJECT_DIR/symfony.lock" ]] || {
  >&2 echo "Error: not a Symfony project directory."
  exit 1
}

echo "> Generating diagram..."

UML_FILE="${PROJECT_DIR}classes.puml"
PNG_FILE="${PROJECT_DIR}classes.png"

HEADER="$(cat << EOB
@startuml

!define table(x) entity x << (T, white) >>
!define primary_key(x) <b><&key> x</b>
!define column(x) <&media-record> x
EOB
)"

FOOTER="@enduml"

declare -a RELATIONS

read_relation() {
  unset relation_data
  declare -gA relation_data
  IFS=',' read -a data <<< "$1"
  for info in "${data[@]}"; do
    [[ $info =~ ^[[:blank:]]?(.+):[[:blank:]](.+)$ ]] &&
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      [[ $key == "targetEntity" ]] &&
        value="${value/::class}"
      relation_data[$key]="$value"
  done
  # for key in "${!relation_data[@]}"; do
  #   echo -n "${key}: ${relation_data[$key]} / "
  # done
  # echo
}

read_field() {
  unset field_data
  declare -gA field_data
  IFS=',' read -a data <<< "$1"
  for info in "${data[@]}"; do
    [[ $info =~ ^[[:blank:]]?(.+):[[:blank:]](.+)$ ]] && {
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      [[ $key == "type" ]] &&
        value="${value//\'}"
      field_data[$key]="$value"
    }
  done
}

read_entity() {
  # Get entity name, fields and data types
  PRIMARY='^#\[ORM\\Id\]$'
  COLUMN='^#\[ORM\\Column\(?(.+)?\)\]$'
  FOREIGN12='^#\[ORM\\OneToMany\((.+)\)\]$'
  FOREIGN21='^#\[ORM\\ManyToOne\((.+)\)\]$'
  FOREIGN11='^#\[ORM\\OneToOne\((.+)\)\]$'
  FOREIGN22='^#\[ORM\\ManyToMany\((.+)\)\]$'
  CLASS='^class[[:blank:]]([A-Za-z]+)([[:space:]].*)?$'
  FIELD='^private[[:blank:]](readonly)?[[:blank:]]?\??\\?([A-Za-z0-9]+)?[[:blank:]]?\$([A-Za-z0-9_-]+)'

  while read -r line; do

    [[ $line =~ $CLASS ]] && {
      entity="${BASH_REMATCH[1]}"
      echo -e "\ntable( ${entity} ) {" >> "$UML_FILE"
      echo " → Processing $entity"
    }

    #[ORM\OneToMany(targetEntity: Record::class, mappedBy: 'artist_id', orphanRemoval: true, cascade: ['persist', 'remove'])]
    #[ORM\Column(type: 'string', length: 255)]

    [[ $line =~ $PRIMARY ]] && primary=1
    [[ $line =~ $FOREIGN12 ]] && { foreign12=1; read_relation "${BASH_REMATCH[1]}"; }
    [[ $line =~ $FOREIGN21 ]] && { foreign21=1; read_relation "${BASH_REMATCH[1]}"; }
    [[ $line =~ $FOREIGN11 ]] && { foreign11=1; read_relation "${BASH_REMATCH[1]}"; }
    [[ $line =~ $FOREIGN22 ]] && { foreign22=1; read_relation "${BASH_REMATCH[1]}"; }

    [[ $line =~ $COLUMN ]] && read_field "${BASH_REMATCH[1]}"

    [[ $line =~ $FIELD ]] && {
      if [[ ${#BASH_REMATCH[@]} -eq 4 ]]; then
        field="${BASH_REMATCH[3]}"
        datatype="${BASH_REMATCH[2]}"
      else
        field="${BASH_REMATCH[2]}"
        datatype="${BASH_REMATCH[1]}"
      fi

      [[ ${field_data[unique]} == true ]] &&
        unique="UNIQUE"
      [[ ${field_data[unique]} == true ]] ||
        unset unique

      [[ $field ]] || {
        field=$datatype
        datatype="${field_data[type]}"
      }

      [[ $datatype ]] ||
        datatype="${field_data[type]}"

      [[ $primary ]] && {
        echo "  primary_key( $field ) : $datatype" >> "$UML_FILE"
        unset primary
        continue
      }
      [[ $foreign12 ]] && {
        [[ $datatype == "Collection" ]] && {
          unset foreign12
          continue
        }
        target_entity="${relation_data[targetEntity]}"
        [[ $target_entity ]] || target_entity="$datatype"
        [[ $target_entity == "self" ]] && target_entity="$entity"

        # echo "  foreign_key( $field ) : $target_entity <<FK>>" >> "$UML_FILE"
        RELATIONS+=("${entity} \"1\" -- \"*\" ${target_entity}")
        unset foreign12
        continue
      }
      [[ $foreign21 ]] && {
        [[ $datatype == "Collection" ]] && {
          unset foreign21
          continue
        }
        target_entity=${relation_data[targetEntity]}
        [[ $target_entity ]] || target_entity="$datatype"
        [[ $target_entity == "self" ]] && target_entity="$entity"

        # echo "  foreign_key( $field ) : $target_entity <<FK>>" >> "$UML_FILE"
        RELATIONS+=("${entity} \"*\" -- \"1\" ${target_entity}")
        unset foreign21
        continue
      }
      [[ $foreign11 ]] && {
        [[ $datatype == "Collection" ]] && {
          unset foreign11
          continue
        }
        target_entity="${relation_data[targetEntity]}"
        [[ $target_entity == "" ]] && target_entity="$datatype"
        [[ $target_entity == "self" ]] && target_entity="$entity"

        # echo "  foreign_key( $field ) : $target_entity <<FK>>" >> "$UML_FILE"
        RELATIONS+=("${entity} \"1\" -- \"1\" ${target_entity}")
        unset foreign11
        continue
      }
      [[ $foreign22 ]] && {
        [[ $datatype == "Collection" ]] && {
          unset foreign22
          continue
        }
        target_entity="${relation_data[targetEntity]}"
        [[ $target_entity == "" ]] && target_entity="$datatype"
        [[ $target_entity == "self" ]] && target_entity="$entity"

        # echo "  foreign_key( $field ) : $target_entity <<FK>>" >> "$UML_FILE"
        RELATIONS+=("${entity} \"*\" -- \"*\" ${target_entity}")
        unset foreign22
        continue
      }
      
      echo "  column( $field ) : $datatype $unique" >> "$UML_FILE"

    }
  done < $1
  echo "}" >> "$UML_FILE"
}

echo "$HEADER" > "$UML_FILE"

for file in $PROJECT_DIR/src/Entity/*; do
  read_entity "$file"
done

echo >> "$UML_FILE"

for relation in "${RELATIONS[@]}"; do
  echo "$relation" >> "$UML_FILE"
done

echo -e "\n$FOOTER" >> "$UML_FILE"

# Check whether plantuml executable is available.
which plantuml &> /dev/null
_puml=$?

[[ $_puml ]] && {
  echo "> Compiling..."
  plantuml "$UML_FILE" || {
    >&2 echo "An error occured."
    exit 1
  }
}

[[ $_puml ]] || {
  >&2 echo "Error: could not find 'plantuml' executable. No image generated."
  >&2 echo "Saved: ${UML_FILE}"
  exit 1
}

echo "Done."
echo "Saved ${PNG_FILE}"

# Display diagram if feh is available.
which feh &> /dev/null && feh --zoom 90 "$PNG_FILE"
