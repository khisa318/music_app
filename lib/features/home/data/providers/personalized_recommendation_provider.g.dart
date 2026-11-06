// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personalized_recommendation_provider.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserPreferenceProfileAdapter extends TypeAdapter<UserPreferenceProfile> {
  @override
  final typeId = 20;

  @override
  UserPreferenceProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserPreferenceProfile(
      artistAffinities: (fields[0] as Map).cast<String, double>(),
      songAffinities: (fields[1] as Map).cast<String, double>(),
      skipCounts: (fields[2] as Map).cast<String, int>(),
      completionCounts: (fields[3] as Map).cast<String, int>(),
      lastUpdated: fields[4] as DateTime,
      totalSongsAnalyzed: (fields[5] as num).toInt(),
      preferredArtistIds: (fields[6] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, UserPreferenceProfile obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.artistAffinities)
      ..writeByte(1)
      ..write(obj.songAffinities)
      ..writeByte(2)
      ..write(obj.skipCounts)
      ..writeByte(3)
      ..write(obj.completionCounts)
      ..writeByte(4)
      ..write(obj.lastUpdated)
      ..writeByte(5)
      ..write(obj.totalSongsAnalyzed)
      ..writeByte(6)
      ..write(obj.preferredArtistIds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreferenceProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
